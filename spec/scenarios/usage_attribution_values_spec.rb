# frozen_string_literal: true

require "rails_helper"

describe "Usage attribution values Scenarios" do
  let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, external_id: "sub_1", started_at: 1.month.ago) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "tokens", field_name: "tokens") }

  # The test environment uses a null cache store, which would make every combination look new.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  let(:batch) do
    [
      {tokens: 10, department_id: "rnd", user_id: "alice", api_key: "key-1"},
      {tokens: 20, user_id: "alice", department_id: "rnd", api_key: "key-1"},
      {tokens: 5, department_id: "rnd", userId: "bob"},
      {tokens: 7}
    ]
  end

  def create_usage_attribution_type(params)
    api_call do
      post_with_token(organization, "/api/v1/usage_attribution_types", {usage_attribution_type: params})
    end
  end

  def create_single_event(properties)
    event = {code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id: SecureRandom.uuid, properties:}

    api_call do
      post_with_token(organization, "/api/v1/events", {event:})
    end
  end

  def create_events_batch(properties_list, **kwargs)
    events = properties_list.map do |properties|
      {code: billable_metric.code, external_subscription_id: subscription.external_id, transaction_id: SecureRandom.uuid, properties:}
    end

    api_call(**kwargs) do
      post_with_token(organization, "/api/v1/events/batch", {events:})
    end
  end

  # [type code, value, parent value] for each attribution value of the customer.
  def account_tree_values
    UsageAttributionValue.where(customer:).includes(:usage_attribution_type, :parent).map do |value|
      [value.usage_attribution_type.code, value.value, value.parent&.value]
    end
  end

  before { allow(Rails).to receive(:cache).and_return(cache) }

  context "with the account_tree feature flag" do
    before do
      create_usage_attribution_type(code: "department", role: "hierarchical", attribution_keys: ["department_id"])
      create_usage_attribution_type(code: "user", role: "hierarchical", attribution_keys: %w[user_id userId], parent_code: "department")
      create_usage_attribution_type(code: "api_key", role: "flat", attribution_keys: ["api_key"])
    end

    it "creates the account tree values of ingested events, once per combination" do
      # A batch: alice twice with her labels in another order, bob through the fallback key, and an
      # event without attribution keys.
      create_events_batch(batch)

      expect(account_tree_values).to match_array([
        ["department", "rnd", nil],
        ["user", "alice", "rnd"],
        ["user", "bob", "rnd"],
        ["api_key", "key-1", nil]
      ])

      # The same combinations again: already seen, so no job is enqueued.
      expect { create_events_batch(batch, perform_jobs: false) }
        .not_to have_enqueued_job(UsageAttributionValues::TrackJob)

      # A single event with a new department and user extends the tree.
      create_single_event({tokens: 3, department_id: "sales", user_id: "carol"})

      expect(account_tree_values).to match_array([
        ["department", "rnd", nil],
        ["user", "alice", "rnd"],
        ["user", "bob", "rnd"],
        ["api_key", "key-1", nil],
        ["department", "sales", nil],
        ["user", "carol", "sales"]
      ])
    end

    context "when the events carry no attribution key" do
      let(:batch) { [{tokens: 10}, {tokens: 5, region: "eu"}] }

      it "tracks nothing" do
        expect { create_events_batch(batch, perform_jobs: false) }
          .not_to have_enqueued_job(UsageAttributionValues::TrackJob)

        perform_all_enqueued_jobs

        expect(account_tree_values).to be_empty
      end
    end

    context "when attribution keys are invalid" do
      let(:batch) do
        [
          # Keys that are not configured: another name, another case.
          {tokens: 1, department: "rnd", UserId: "bob"},
          # Values that cannot identify an attribution value: empty, null, nested, too long.
          {tokens: 1, department_id: "", user_id: nil},
          {tokens: 1, user_id: {id: "alice"}, api_key: ["key-1"]},
          {tokens: 1, api_key: "k" * 256},
          # A valid department next to an invalid user.
          {tokens: 1, department_id: "ops", user_id: {id: "dave"}}
        ]
      end

      it "only tracks the valid values" do
        create_events_batch(batch)

        expect(account_tree_values).to eq([["department", "ops", nil]])
      end
    end
  end

  context "with a multi-level tree" do
    before do
      create_usage_attribution_type(code: "department", role: "hierarchical", attribution_keys: ["department_id"])
      create_usage_attribution_type(code: "team", role: "hierarchical", attribution_keys: ["team_id"], parent_code: "department")
      create_usage_attribution_type(code: "user", role: "hierarchical", attribution_keys: ["user_id"], parent_code: "team")
      create_usage_attribution_type(code: "model", role: "flat", attribution_keys: ["model"])
    end

    let(:batch) do
      [
        {tokens: 10, department_id: "rnd", team_id: "eng", user_id: "alice", model: "opus"},
        {tokens: 20, department_id: "rnd", team_id: "eng", user_id: "bob", model: "sonnet"},
        {tokens: 30, department_id: "rnd", team_id: "data", user_id: "carol", model: "opus"},
        {tokens: 40, department_id: "sales", team_id: "emea", user_id: "dave"},
        # A numeric identifier is stored as the events-processor stamps it.
        {tokens: 50, department_id: "sales", team_id: "emea", user_id: 1234567},
        # A partial chain: the user has no team in this event.
        {tokens: 60, department_id: "rnd", user_id: "erin"}
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

    it "links every value to its parent, level by level" do
      create_events_batch(batch)

      expect(account_tree_values).to match_array(expected_tree)

      # alice moves to another team: placement follows her most recent event.
      create_single_event({tokens: 5, department_id: "rnd", team_id: "data", user_id: "alice"})

      expect(account_tree_values).to match_array(expected_tree - [["user", "alice", "eng"]] + [["user", "alice", "data"]])
    end
  end

  context "without the account_tree feature flag" do
    let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true, feature_flags: []) }

    before do
      [
        {code: "department", attribution_keys: ["department_id"]},
        {code: "user", attribution_keys: ["user_id"]}
      ].each { |attributes| create(:usage_attribution_type, organization:, **attributes) }
    end

    it "does not create attribution values" do
      create_events_batch(batch)

      expect(account_tree_values).to be_empty
    end
  end
end
