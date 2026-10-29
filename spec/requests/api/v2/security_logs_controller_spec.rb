# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::SecurityLogsController, :premium, clickhouse: true do
  let(:organization) { create(:organization, premium_integrations: ["security_logs"]) }
  let(:user) { create(:user, email: "user@example.test") }
  let(:to_date) { Time.current.iso8601 }
  let(:returned_ids) { json[:security_logs].map { |l| l[:log_id] } }

  # Builds a log with constant identifier fields and a fixed user, so the payload can be asserted
  # against literal values. resources and device_info are parsed one level deep by the model.
  def create_security_log(resources: {"user_email" => "test@example.com"}, device_info: {"browser" => "Chrome"}, **extra)
    membership = create(:membership, organization:, user:)
    create(
      :clickhouse_security_log,
      membership:,
      log_id: "security-log-1",
      log_type: "user",
      log_event: "user.signed_up",
      resources:,
      device_info:,
      **extra
    )
  end

  def stored_security_log
    organization.security_logs.find_by(log_id: "security-log-1")
  end

  # The full serialized object the endpoint returns. `json` symbolizes keys, so the parsed map
  # values are symbol-keyed too. The timestamps are read from the stored record because ClickHouse
  # keeps millisecond precision while the in-memory factory time has microseconds (the v2 render
  # path emits microseconds).
  def expected_payload(record, resources:, device_info:)
    {
      log_id: "security-log-1",
      log_type: "user",
      log_event: "user.signed_up",
      user_email: "user@example.test",
      logged_at: record.logged_at.iso8601(6),
      created_at: record.created_at.iso8601(6),
      resources:,
      device_info:
    }
  end

  describe "GET /api/v2/security_logs" do
    subject(:request) { get_with_token(organization, "/api/v2/security_logs", params) }

    let(:params) { {to_date:} }

    context "with a premium organization without the `security_logs` feature" do
      let(:organization) { create(:organization, premium_integrations: []) }

      it "returns a forbidden error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("forbidden")
      end
    end

    context "without the product catalog", product_catalog: false do
      it "returns a feature_unavailable error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
        expect(organization.reload).not_to be_product_catalog_enabled
      end
    end

    context "when to_date is missing" do
      let(:params) { {} }

      it "returns the value_is_mandatory validation error" do
        request

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "validation_errors",
          details: [{code: "value_is_mandatory", field: "to_date", meta: {}}]
        )
      end
    end

    context "with stored security logs" do
      before do
        create_security_log(
          logged_at: 1.hour.ago,
          resources: {"detail" => "{\"key\":\"value\"}"},
          device_info: {"meta" => "[1,2,3]"}
        )
      end

      it "returns the full entry with resources and device_info parsed as JSON" do
        request

        expect(response).to have_http_status(:success)
        expect(json[:security_logs].sole).to eq(
          expected_payload(
            stored_security_log,
            resources: {detail: {key: "value"}},
            device_info: {meta: [1, 2, 3]}
          )
        )
      end

      it "does not return a total count by default" do
        request

        expect(json[:meta].keys).to eq(%i[next_cursor prev_cursor])
      end
    end

    shared_examples "a tie-breaking cursor walk" do
      before do
        5.times { create(:clickhouse_security_log, organization:, logged_at:) }
      end

      let(:ordered_ids) do
        organization.security_logs.order(logged_at: :desc, log_id: :desc).pluck(:log_id)
      end

      def fetch_page(extra = {})
        get_with_token(organization, "/api/v2/security_logs", {to_date:}.merge(extra))
        json
      end

      it "returns every row exactly once, breaking the tie on the log_id" do
        forward = []
        page = fetch_page(limit: 2)
        expect(page[:meta][:prev_cursor]).to be_nil

        loop do
          forward.concat(page[:security_logs].map { it[:log_id] })
          break unless page[:meta][:next_cursor]

          page = fetch_page(limit: 2, after: page[:meta][:next_cursor])
        end

        expect(forward).to eq(ordered_ids)
        expect(forward.uniq).to eq(forward)
      end

      it "walks back to the first page with the previous cursor" do
        last_page = fetch_page(limit: 2)
        last_page = fetch_page(limit: 2, after: last_page[:meta][:next_cursor]) while last_page[:meta][:next_cursor]

        backward = []
        page = last_page
        loop do
          backward.unshift(*page[:security_logs].map { it[:log_id] })
          break unless page[:meta][:prev_cursor]

          page = fetch_page(limit: 2, before: page[:meta][:prev_cursor])
        end

        expect(backward).to eq(ordered_ids)
      end
    end

    context "when walking the cursor over rows sharing a sub-second logged_at" do
      let(:logged_at) { 1.hour.ago.change(usec: 123_000) }

      it_behaves_like "a tie-breaking cursor walk"
    end

    context "when walking the cursor over rows sharing a second-precision logged_at" do
      let(:logged_at) { 1.hour.ago.change(usec: 0) }

      it_behaves_like "a tie-breaking cursor walk"
    end

    context "with an invalid cursor" do
      let(:params) { {to_date:, after: "not-a-cursor!"} }

      it "returns the v2 error body" do
        request

        expect(response).to have_http_status(:bad_request)
        expect(json).to eq(
          code: "invalid_pagination_cursor",
          details: [{code: "malformed", field: "after", meta: {}}]
        )
      end
    end
  end

  describe "GET /api/v2/security_logs/:log_id" do
    subject(:request) { get_with_token(organization, "/api/v2/security_logs/#{security_log.log_id}") }

    let!(:security_log) { create_security_log(logged_at: 1.hour.ago) }

    context "with a premium organization without the `security_logs` feature" do
      let(:organization) { create(:organization, premium_integrations: []) }

      it "returns a forbidden error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("forbidden")
      end
    end

    context "without the product catalog", product_catalog: false do
      it "returns a feature_unavailable error" do
        request

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    it "returns the full security log object" do
      request

      expect(response).to have_http_status(:success)
      expect(json[:security_log]).to eq(
        expected_payload(
          stored_security_log,
          resources: {user_email: "test@example.com"},
          device_info: {browser: "Chrome"}
        )
      )
    end

    context "when the security log does not exist" do
      subject(:request) { get_with_token(organization, "/api/v2/security_logs/unknown") }

      it "returns a not found error" do
        request

        expect(response).to be_v2_not_found_error("security_log")
      end
    end
  end
end
