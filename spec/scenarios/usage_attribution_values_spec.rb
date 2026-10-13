# frozen_string_literal: true

require "rails_helper"

describe "Usage attribution values Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, external_id: "sub_1", started_at: 1.month.ago) }
  let(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_USAGE_ATTRIBUTION_VALUES_TOPIC"]) }

  let(:reported_labels) do
    [
      {"department" => "rnd", "team" => "eng", "user" => "alice", "model" => "opus"},
      {"department" => "rnd", "team" => "eng", "user" => "bob", "model" => "sonnet"},
      {"department" => "rnd", "team" => "data", "user" => "carol", "model" => "opus"},
      {"department" => "sales", "team" => "emea", "user" => "dave"},
      {"department" => "sales", "team" => "emea", "user" => "1234567"},
      # A partial chain: the user has no team in this event.
      {"department" => "rnd", "user" => "erin"}
    ]
  end

  let(:expected_tree) do
    [
      ["department", "rnd", nil],
      ["department", "sales", nil],
      ["team", "eng", "rnd"],
      ["team", "data", "rnd"],
      ["team", "emea", "sales"],
      ["user", "alice", "eng"],
      ["user", "bob", "eng"],
      ["user", "carol", "data"],
      ["user", "dave", "emea"],
      ["user", "1234567", "emea"],
      ["user", "erin", nil],
      ["model", "opus", nil],
      ["model", "sonnet", nil]
    ]
  end

  def create_usage_attribution_type(params)
    api_call do
      post_with_token(organization, "/api/v1/usage_attribution_types", {usage_attribution_type: params})
    end
  end

  # Reports values the way the events-processor does once it has enriched events.
  def report_values(labels_list, at: Time.current)
    labels_list.each do |labels|
      message = {organization_id: organization.id, subscription_id: subscription.id, attribution_labels: labels, timestamp: at.to_f}
      karafka.produce(message.to_json)
    end

    consumer.consume
  end

  # [type code, value, parent value] for each attribution value of the customer.
  def account_tree_values
    UsageAttributionValue.where(customer:).includes(:usage_attribution_type, :parent).map do |value|
      [value.usage_attribution_type.code, value.value, value.parent&.value]
    end
  end

  context "with the account_tree feature flag" do
    before do
      create_usage_attribution_type(code: "department", role: "hierarchical", attribution_keys: ["department_id"])
      create_usage_attribution_type(code: "team", role: "hierarchical", attribution_keys: ["team_id"], parent_code: "department")
      create_usage_attribution_type(code: "user", role: "hierarchical", attribution_keys: ["user_id"], parent_code: "team")
      create_usage_attribution_type(code: "model", role: "flat", attribution_keys: ["model"])
    end

    it "builds the account tree from the reported values" do
      report_values(reported_labels)

      expect(account_tree_values).to match_array(expected_tree)

      # The same values reported again, by another processor instance or a replayed batch.
      expect { report_values(reported_labels) }.not_to change(UsageAttributionValue, :count)

      # alice moves to another team: placement follows her most recent event.
      report_values([{"department" => "rnd", "team" => "data", "user" => "alice"}], at: 1.minute.from_now)

      expect(account_tree_values).to match_array(expected_tree - [["user", "alice", "eng"]] + [["user", "alice", "data"]])
    end
  end

  context "without the account_tree feature flag" do
    let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true, feature_flags: []) }

    before do
      department = create(:usage_attribution_type, organization:, code: "department", attribution_keys: ["department_id"])
      create(:usage_attribution_type, organization:, code: "user", attribution_keys: ["user_id"], parent: department)
    end

    it "does not create attribution values" do
      report_values([{"department" => "rnd", "user" => "alice"}])

      expect(account_tree_values).to be_empty
    end
  end
end
