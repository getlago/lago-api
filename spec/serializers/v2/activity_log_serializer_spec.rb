# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V2::ActivityLogSerializer, clickhouse: true do
  subject(:serializer) { described_class.new(activity_log, root_name: "activity_log") }

  let(:user) { create(:user, email: "user@example.test") }
  let(:membership) { create(:membership, user:) }
  let(:activity_log) do
    create(
      :clickhouse_activity_log,
      membership:,
      activity_id: "activity-1",
      activity_type: "billable_metric.created",
      activity_source: "api",
      external_customer_id: "customer-1",
      external_subscription_id: "subscription-1",
      activity_object:,
      activity_object_changes:
    )
  end

  let(:result) { JSON.parse(serializer.to_json)["activity_log"] }

  # Constant fields with the two JSON maps passed in. `resource_id` and the timestamps are read
  # from the record: the model requires the resource to reference a real record, and the timestamps
  # are assigned at creation. The serializer renders the timestamps at whole seconds by default.
  def expected_payload(activity_object:, activity_object_changes:)
    {
      "activity_id" => "activity-1",
      "activity_type" => "billable_metric.created",
      "activity_source" => "api",
      "activity_object" => activity_object,
      "activity_object_changes" => activity_object_changes,
      "user_email" => "user@example.test",
      "resource_id" => activity_log.resource_id,
      "resource_type" => "BillableMetric",
      "external_customer_id" => "customer-1",
      "external_subscription_id" => "subscription-1",
      "logged_at" => activity_log.logged_at.iso8601,
      "created_at" => activity_log.created_at.iso8601
    }
  end

  context "when the map values are JSON-encoded" do
    let(:activity_object) { {"foo" => '{"a": 1}', "baz" => "qux"} }
    let(:activity_object_changes) { {"foo" => '{"old": "bar", "new": "baz"}'} }

    it "serializes the object and parses the JSON values one level deep" do
      expect(result).to eq(
        expected_payload(
          activity_object: {"foo" => {"a" => 1}, "baz" => "qux"},
          activity_object_changes: {"foo" => {"old" => "bar", "new" => "baz"}}
        )
      )
    end
  end

  context "when a map holds a non-JSON value" do
    let(:activity_object) { {"foo" => "bar"} }
    let(:activity_object_changes) { {"foo" => "not json"} }

    it "returns the raw value" do
      expect(result).to eq(
        expected_payload(
          activity_object: {"foo" => "bar"},
          activity_object_changes: {"foo" => "not json"}
        )
      )
    end
  end

  context "when a map value parses to a JSON scalar" do
    let(:activity_object) { {"n" => "5"} }
    let(:activity_object_changes) { {"foo" => "bar"} }

    it "keeps the original string instead of coercing it" do
      expect(result).to eq(
        expected_payload(
          activity_object: {"n" => "5"},
          activity_object_changes: {"foo" => "bar"}
        )
      )
    end
  end
end
