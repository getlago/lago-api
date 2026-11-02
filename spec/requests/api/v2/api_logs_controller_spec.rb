# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ApiLogsController, clickhouse: true do
  subject { get_with_token(organization, path, params) }

  let(:organization) { create(:organization) }
  let(:request_body) { {"foo" => "bar", "baz" => "qux"} }
  let(:request_response) { {"foo" => "bar"} }
  let(:api_log) do
    create(
      :clickhouse_api_log,
      organization:,
      request_id: "api-log-1",
      client: "RSpec",
      http_method: "post",
      http_status: 200,
      request_origin: "https://lago.test",
      request_path: "/api/v1/test-endpoint",
      api_version: "v1",
      request_body:,
      request_response:
    )
  end
  let(:params) { {} }

  # The full serialized object the endpoint returns. `json` symbolizes keys, so the parsed map
  # values are symbol-keyed too. The timestamps are read from the stored record because ClickHouse
  # keeps millisecond precision while the in-memory factory time has microseconds (the v2 render
  # path emits microseconds). The two map fields are this serializer's parsed output.
  def expected_payload(record, request_body:, request_response:)
    {
      request_id: "api-log-1",
      client: "RSpec",
      http_method: "post",
      http_status: 200,
      request_origin: "https://lago.test",
      request_path: "/api/v1/test-endpoint",
      request_body:,
      request_response:,
      api_version: "v1",
      logged_at: record.logged_at.iso8601(6),
      created_at: record.created_at.iso8601(6)
    }
  end

  def stored_api_log
    Clickhouse::ApiLog.where(organization_id: organization.id).find_by(request_id: "api-log-1")
  end

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
        expect(json).to eq(code: "feature_unavailable", details: [])
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

      it "returns the full api log object and cursor meta" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:api_logs].sole).to eq(
          expected_payload(
            stored_api_log,
            request_body: {foo: "bar", baz: "qux"},
            request_response: {foo: "bar"}
          )
        )
        expect(json[:meta].keys).to eq(%i[next_cursor prev_cursor])
      end

      context "when request_body and request_response hold JSON-encoded values" do
        let(:request_body) { {"metadata" => "{\"foo\":\"bar\"}", "plain" => "hello"} }
        let(:request_response) { {"items" => "[1,2,3]", "note" => "not-json"} }

        it "returns the full object with the JSON values parsed one level deep" do
          subject

          expect(json[:api_logs].sole).to eq(
            expected_payload(
              stored_api_log,
              request_body: {metadata: {foo: "bar"}, plain: "hello"},
              request_response: {items: [1, 2, 3], note: "not-json"}
            )
          )
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
          expect(json).to eq(
            code: "invalid_pagination_cursor",
            details: [{code: "malformed", field: "after", meta: {}}]
          )
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
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end

    context "with premium organization", :premium do
      let(:request_body) { {"metadata" => "{\"foo\":\"bar\"}"} }
      let(:request_response) { {"items" => "[1,2,3]"} }

      include_examples "requires API permission", "api_log", "read"

      it "returns the full api log object with parsed JSON fields" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:api_log]).to eq(
          expected_payload(
            stored_api_log,
            request_body: {metadata: {foo: "bar"}},
            request_response: {items: [1, 2, 3]}
          )
        )
      end

      context "when the request_id is unknown" do
        let(:path) { "/api/v2/api_logs/unknown-request-id" }

        it "returns a not found error" do
          subject

          expect(response).to be_v2_not_found_error("api_log")
        end
      end
    end
  end
end
