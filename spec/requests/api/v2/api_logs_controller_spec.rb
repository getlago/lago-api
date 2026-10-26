# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ApiLogsController, clickhouse: true do
  subject { get_with_token(organization, path, params) }

  let(:organization) { create(:organization) }
  let(:api_log) { create(:clickhouse_api_log, organization:) }
  let(:params) { {} }

  describe "GET /api/v2/api_logs" do
    let(:path) { "/api/v2/api_logs" }

    before { api_log }

    # ClickHouse inserts are asynchronous (async_insert), so each row becomes
    # queryable a short moment after it is written. A cursor walk asserts an
    # exact row set, so it waits until every row is visible before reading.
    def wait_for_api_logs_count(count)
      20.times do
        break if Clickhouse::ApiLog.where(organization_id: organization.id).count >= count

        sleep 0.1
      end
    end

    def fetch_page(page_params)
      get_with_token(organization, path, page_params)
      json
    end

    def listed_ids(page_params = {})
      fetch_page(page_params.merge(limit: 100))[:api_logs].map { it[:request_id] }
    end

    # Walks the whole list forward one small page at a time, then backward, and
    # asserts each direction returns the full ordered list with no row dropped
    # or repeated.
    def expect_full_cursor_walk(all_ids, page_limit)
      forward = []
      page = fetch_page(limit: page_limit)
      expect(page[:meta][:prev_cursor]).to be_nil
      loop do
        forward.concat(page[:api_logs].map { it[:request_id] })
        break unless page[:meta][:next_cursor]

        page = fetch_page(limit: page_limit, after: page[:meta][:next_cursor])
      end

      backward = []
      loop do
        backward.unshift(*page[:api_logs].map { it[:request_id] })
        break unless page[:meta][:prev_cursor]

        page = fetch_page(limit: page_limit, before: page[:meta][:prev_cursor])
      end

      expect(forward).to eq(all_ids)
      expect(backward).to eq(all_ids)
    end

    context "with free organization" do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:error]).to eq("Forbidden")
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "without product catalog enabled", :premium, product_catalog: false do
      it "requires the product catalog" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
        expect(organization.reload).not_to be_product_catalog_enabled
      end
    end

    context "with premium organization", :premium do
      include_examples "requires API permission", "api_log", "read"

      it "returns api logs with parsed JSON fields and cursor meta" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:api_logs].map { |l| l[:request_id] }).to include(api_log.request_id)
        expect(json[:meta].keys).to eq(%i[next_cursor prev_cursor])
      end

      context "when request_body and request_response hold JSON-encoded values" do
        let(:api_log) do
          create(
            :clickhouse_api_log,
            organization:,
            request_body: {"metadata" => "{\"foo\":\"bar\"}", "plain" => "hello"},
            request_response: {"items" => "[1,2,3]", "note" => "not-json"}
          )
        end

        it "parses them one level deep" do
          subject

          entry = json[:api_logs].find { |l| l[:request_id] == api_log.request_id }
          expect(entry[:request_body]).to eq(metadata: {foo: "bar"}, plain: "hello")
          expect(entry[:request_response]).to eq(items: [1, 2, 3], note: "not-json")
        end
      end

      context "when filtering by from_date" do
        let(:params) { {from_date: api_log.logged_at.iso8601} }
        let(:older_api_log) { create(:clickhouse_api_log, organization:, logged_at: 2.days.ago) }

        before { older_api_log }

        it "returns api logs for the specified date range" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:api_logs].map { |l| l[:request_id] }).to eq([api_log.request_id])
        end
      end

      context "when ClickHouse is not available" do
        before { allow(Utils::ApiLog).to receive(:available?).and_return(false) }

        it "returns a forbidden error" do
          subject

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end

      context "with an invalid cursor" do
        let(:params) { {after: "not-a-cursor!"} }

        it "returns the v2 error body" do
          subject

          expect(response).to have_http_status(:bad_request)
          expect(json[:status]).to eq(400)
          expect(json[:error]).to eq("Bad Request")
          expect(json[:code]).to eq("invalid_pagination_cursor")
        end
      end
    end

    # Production logged_at is second-precision (producers emit Time.current.iso8601
    # with no fractional part), so several rows routinely share the exact same
    # logged_at. The page must then break the tie on request_id and page through
    # them without dropping or repeating a row.
    context "with more rows than the page limit sharing an identical second-precision logged_at", :premium do
      let(:api_log) { nil }
      let(:shared_logged_at) { Time.zone.parse("2026-09-28T10:00:00Z") }

      before do
        %w[req-a req-b req-c req-d req-e].each do |request_id|
          create(:clickhouse_api_log, organization:, request_id:, logged_at: shared_logged_at)
        end

        wait_for_api_logs_count(5)
      end

      it "breaks the logged_at tie on request_id descending" do
        expect(listed_ids).to eq(%w[req-e req-d req-c req-b req-a])
      end

      it "returns every row exactly once, walking forward then backward with a smaller page" do
        expect_full_cursor_walk(listed_ids, 2)
      end
    end

    # Defensive: even though production logged_at is second-precision, ClickHouse
    # stores it as DateTime64(3). Rows in the same second with different
    # milliseconds must not collapse onto the second boundary in the cursor
    # keyset, or the walk would skip the rows past the anchor's second.
    context "with rows in the same second but different sub-second logged_at", :premium do
      let(:api_log) { nil }

      before do
        create(:clickhouse_api_log, organization:, request_id: "req-a", logged_at: Time.zone.parse("2026-09-28T10:00:00.100Z"))
        create(:clickhouse_api_log, organization:, request_id: "req-b", logged_at: Time.zone.parse("2026-09-28T10:00:00.200Z"))
        create(:clickhouse_api_log, organization:, request_id: "req-c", logged_at: Time.zone.parse("2026-09-28T10:00:00.300Z"))
        create(:clickhouse_api_log, organization:, request_id: "req-d", logged_at: Time.zone.parse("2026-09-28T10:00:00.400Z"))
        create(:clickhouse_api_log, organization:, request_id: "req-e", logged_at: Time.zone.parse("2026-09-28T10:00:00.500Z"))

        wait_for_api_logs_count(5)
      end

      it "orders by the sub-second logged_at descending" do
        expect(listed_ids).to eq(%w[req-e req-d req-c req-b req-a])
      end

      it "returns every row exactly once, walking forward then backward with a smaller page" do
        expect_full_cursor_walk(listed_ids, 2)
      end
    end
  end

  describe "GET /api/v2/api_logs/:request_id" do
    let(:path) { "/api/v2/api_logs/#{api_log.request_id}" }

    context "with free organization" do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:error]).to eq("Forbidden")
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with premium organization", :premium do
      let(:api_log) do
        create(
          :clickhouse_api_log,
          organization:,
          request_body: {"metadata" => "{\"foo\":\"bar\"}"},
          request_response: {"items" => "[1,2,3]"}
        )
      end

      include_examples "requires API permission", "api_log", "read"

      it "returns the api log with parsed JSON fields" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:api_log]).to include(
          request_id: api_log.request_id,
          http_method: api_log.http_method,
          logged_at: api_log.logged_at.iso8601
        )
        expect(json[:api_log][:request_body]).to eq(metadata: {foo: "bar"})
        expect(json[:api_log][:request_response]).to eq(items: [1, 2, 3])
      end

      context "when the request_id is unknown" do
        let(:path) { "/api/v2/api_logs/unknown-request-id" }

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("api_log")
        end
      end
    end
  end
end
