# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ActivityLogsController, clickhouse: true do
  # `organization` stays a plain Postgres record: the product-catalog before hook forces it
  # during setup, before the clickhouse net-connect is allowed, so it must not touch ClickHouse.
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:activity_log) { create(:clickhouse_activity_log, membership:) }

  describe "GET /api/v2/activity_logs" do
    subject { get_with_token(organization, "/api/v2/activity_logs", params) }

    let(:params) { {} }

    before { activity_log }

    context "with free organization" do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with premium organization", :premium do
      include_examples "requires API permission", "activity_log", "read"

      context "with JSON-encoded fields (AC1)" do
        let(:activity_log) do
          create(
            :clickhouse_activity_log,
            membership:,
            activity_object: {"foo" => '{"a": 1}', "baz" => "qux"},
            activity_object_changes: {"foo" => '{"old": "bar", "new": "baz"}'}
          )
        end

        it "returns the parsed JSON values" do
          subject

          expect(response).to have_http_status(:success)
          returned = json[:activity_logs].find { |l| l[:activity_id] == activity_log.activity_id }
          expect(returned[:activity_object][:foo]).to eq({a: 1})
          expect(returned[:activity_object][:baz]).to eq("qux")
          expect(returned[:activity_object_changes][:foo]).to eq({old: "bar", new: "baz"})
        end
      end

      context "when a parsed field holds a non-JSON value (AC4)" do
        let(:activity_log) do
          create(:clickhouse_activity_log, membership:, activity_object_changes: {"foo" => "not json"})
        end

        it "returns the raw value" do
          subject

          expect(response).to have_http_status(:success)
          returned = json[:activity_logs].find { |l| l[:activity_id] == activity_log.activity_id }
          expect(returned[:activity_object_changes][:foo]).to eq("not json")
        end
      end

      context "with cursor pagination over rows sharing a second-precision logged_at (AC5)" do
        # Production data: producers emit logged_at as Time.current.iso8601 with no fractional
        # second, so every row in the same second shares an identical logged_at and the page can
        # only break on the activity_id tiebreak. This must page without dropping a row.
        let(:logged_at) { Time.current.change(usec: 0) }
        let(:activity_log) { create(:clickhouse_activity_log, membership:, logged_at:) }
        let(:other_logs) do
          Array.new(4) do
            create(:clickhouse_activity_log, organization:, resource: activity_log.resource, logged_at:)
          end
        end

        before { other_logs }

        it "walks every row exactly once forward then backward, breaking on the activity_id tiebreak" do
          get_with_token(organization, "/api/v2/activity_logs", {limit: 100})
          all_ids = json[:activity_logs].map { it[:activity_id] }
          expect(all_ids.size).to eq(5)

          forward = []
          get_with_token(organization, "/api/v2/activity_logs", {limit: 2})
          expect(json[:meta][:prev_cursor]).to be_nil
          loop do
            forward.concat(json[:activity_logs].map { it[:activity_id] })
            break unless json[:meta][:next_cursor]

            get_with_token(organization, "/api/v2/activity_logs", {limit: 2, after: json[:meta][:next_cursor]})
          end

          backward = []
          loop do
            backward.unshift(*json[:activity_logs].map { it[:activity_id] })
            break unless json[:meta][:prev_cursor]

            get_with_token(organization, "/api/v2/activity_logs", {limit: 2, before: json[:meta][:prev_cursor]})
          end

          expect(forward).to eq(all_ids)
          expect(backward).to eq(all_ids)
          expect(all_ids.uniq).to eq(all_ids)
        end
      end

      context "with cursor pagination over rows sharing a second but differing by milliseconds (AC5)" do
        # Proves the keyset binds the time with sub-second precision: the rows share a whole second
        # but each has a distinct millisecond, so a cursor bound truncated to the second would drop
        # the rows in the anchor's second. Each row must still be returned exactly once.
        let(:base_time) { Time.current.change(usec: 0) }
        let(:activity_log) { create(:clickhouse_activity_log, membership:, logged_at: base_time + 0.1) }
        let(:other_logs) do
          [0.2, 0.3, 0.4, 0.5].map do |offset|
            create(:clickhouse_activity_log, organization:, resource: activity_log.resource, logged_at: base_time + offset)
          end
        end

        before { other_logs }

        it "walks every row exactly once forward then backward across the sub-second boundary" do
          get_with_token(organization, "/api/v2/activity_logs", {limit: 100})
          all_ids = json[:activity_logs].map { it[:activity_id] }
          expect(all_ids.size).to eq(5)

          forward = []
          get_with_token(organization, "/api/v2/activity_logs", {limit: 2})
          expect(json[:meta][:prev_cursor]).to be_nil
          loop do
            forward.concat(json[:activity_logs].map { it[:activity_id] })
            break unless json[:meta][:next_cursor]

            get_with_token(organization, "/api/v2/activity_logs", {limit: 2, after: json[:meta][:next_cursor]})
          end

          backward = []
          loop do
            backward.unshift(*json[:activity_logs].map { it[:activity_id] })
            break unless json[:meta][:prev_cursor]

            get_with_token(organization, "/api/v2/activity_logs", {limit: 2, before: json[:meta][:prev_cursor]})
          end

          expect(forward).to eq(all_ids)
          expect(backward).to eq(all_ids)
          expect(all_ids.uniq).to eq(all_ids)
        end
      end

      context "with an invalid cursor parameter (AC5)" do
        let(:params) { {after: "not-a-cursor!"} }

        it "returns the v2 error body" do
          subject

          expect(response).to have_http_status(:bad_request)
          expect(json).to include(
            status: 400,
            error: "Bad Request",
            code: "invalid_pagination_cursor"
          )
          expect(json[:error_details]).to be_present
        end
      end

      context "when ClickHouse is not available" do
        before { ENV["LAGO_CLICKHOUSE_ENABLED"] = nil }

        it "returns a forbidden error" do
          subject

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end

      context "without product catalog enabled", product_catalog: false do
        it "requires the product catalog (AC5)" do
          subject

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
          expect(organization.reload).not_to be_product_catalog_enabled
        end
      end
    end
  end

  describe "GET /api/v2/activity_logs/:activity_id" do
    subject { get_with_token(organization, "/api/v2/activity_logs/#{activity_id}", {}) }

    let(:activity_id) { activity_log.activity_id }

    before { activity_log }

    context "with free organization" do
      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "with premium organization", :premium do
      include_examples "requires API permission", "activity_log", "read"

      it "returns one activity log" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:activity_log]).to include(
          activity_id: activity_log.activity_id,
          activity_source: activity_log.activity_source,
          logged_at: activity_log.logged_at.iso8601
        )
      end

      context "when the activity log does not exist" do
        let(:activity_id) { "unknown" }

        it "returns a not found error" do
          subject

          expect(response).to be_not_found_error("activity_log")
        end
      end
    end
  end
end
