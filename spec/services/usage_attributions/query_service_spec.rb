# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::QueryService, clickhouse: {clean_before: true} do
  subject(:result) do
    described_class.call(subscription:, group_by:, filters:, from_datetime:, to_datetime:, charges:, split_charge:, limit:, offset:)
  end

  include_context "with clickhouse availability"

  around { |example| travel_to(Time.zone.parse("2026-09-15 12:00:00")) { example.run } }

  let(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["account_tree"]) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_currency: "EUR") }
  let(:started_at) { Time.zone.parse("2026-08-01") }
  let(:subscription) { create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at) }

  let(:tokens_metric) { create(:sum_billable_metric, organization:, code: "tokens", field_name: "tokens") }
  let(:requests_metric) { create(:billable_metric, organization:, code: "requests", aggregation_type: "count_agg") }
  let(:tokens_charge) { create(:standard_charge, plan:, billable_metric: tokens_metric, properties: {"amount" => "0.5"}) }
  let(:requests_charge) { create(:standard_charge, plan:, billable_metric: requests_metric, properties: {"amount" => "2"}) }

  let(:group_by) { "team" }
  let(:filters) { {} }
  let(:from_datetime) { nil }
  let(:to_datetime) { nil }
  let(:charges) { nil }
  let(:split_charge) { nil }
  let(:limit) { 50 }
  let(:offset) { 0 }

  let(:events) do
    [
      {code: "tokens", value: 1000, labels: {"team" => "eng", "user" => "alice", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "tokens", value: 500, labels: {"team" => "eng", "user" => "bob", "model" => "sonnet"}, properties: {"model" => "sonnet"}},
      {code: "tokens", value: 2000, labels: {"team" => "data", "user" => "carol", "model" => "opus"}, properties: {"model" => "opus"}},
      {code: "requests", value: 1, labels: {"team" => "eng", "user" => "alice", "model" => "opus"}},
      {code: "tokens", value: 100, labels: {}},
      {code: "tokens", value: 999, labels: {"team" => "eng", "user" => "alice"}, timestamp: Time.zone.parse("2026-08-20")}
    ]
  end

  def create_event(code:, value:, labels:, properties: {}, timestamp: Time.zone.parse("2026-09-10"), transaction_id: SecureRandom.uuid)
    Clickhouse::EventsEnriched.create!(
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code:,
      timestamp:,
      transaction_id:,
      properties:,
      attribution_labels: labels,
      value: value.to_s,
      decimal_value: value
    )
  end

  def summary(rows)
    rows.map { [it.value, it.amount_cents, it.events_count] }
  end

  def cells_of(row)
    row.cells.sort_by(&:units).map { [it.charge_id, it.charge_filter_id, it.units, it.amount_cents, it.events_count] }
  end

  before do
    create(:usage_attribution_type, organization:, code: "team")
    create(:usage_attribution_type, organization:, code: "user")
    create(:flat_usage_attribution_type, organization:, code: "model")
    tokens_charge
    requests_charge
    events.each { create_event(**it) }
  end

  it "aggregates the current period per node, unattributed first then by amount" do
    expect(result).to be_success
    expect(summary(result.rows)).to eq([[nil, 5_000, 1], ["data", 100_000, 1], ["eng", 75_200, 3]])
    expect(result.groups_count).to eq(3)
    expect(result.total_amount_cents).to eq(180_200)
    expect(result.total_events_count).to eq(5)
    expect(result.from_datetime).to eq(Time.zone.parse("2026-09-01"))
    expect(result.to_datetime).to eq(Time.zone.parse("2026-09-30").end_of_day)
    expect(result.currency).to eq("EUR")
  end

  it "returns the units, amount and events count of each charge" do
    expect(cells_of(result.rows.last)).to eq(
      [
        [requests_charge.id, nil, 1, 200, 1],
        [tokens_charge.id, nil, 1500, 75_000, 2]
      ]
    )
  end

  context "with label filters" do
    let(:group_by) { "user" }
    let(:filters) { {"team" => "eng", "model" => ["opus", "haiku"]} }

    it "narrows the events to the matching labels" do
      expect(summary(result.rows)).to eq([["alice", 50_200, 2]])
    end
  end

  context "with a filter on unattributed usage" do
    let(:group_by) { "user" }
    let(:filters) { {"team" => nil} }

    it "matches the events without the label" do
      expect(summary(result.rows)).to eq([[nil, 5_000, 1]])
    end
  end

  context "with a label value containing a quote" do
    let(:filters) { {"team" => "o'brien"} }

    before { create_event(code: "tokens", value: 10, labels: {"team" => "o'brien"}) }

    it "escapes the value" do
      expect(summary(result.rows)).to eq([["o'brien", 500, 1]])
    end
  end

  context "with a custom window" do
    let(:from_datetime) { Time.zone.parse("2026-07-25") }
    let(:to_datetime) { Time.zone.parse("2026-08-24") }

    it "clamps the window to the subscription lifetime" do
      expect(summary(result.rows)).to eq([["eng", 49_950, 1]])
      expect(result.from_datetime).to eq(started_at)
      expect(result.to_datetime).to eq(to_datetime)
    end
  end

  context "with a terminated subscription" do
    let(:subscription) do
      create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at,
        status: :terminated, terminated_at: Time.zone.parse("2026-09-05"))
    end

    it "stops the window at the termination" do
      expect(result.to_datetime).to eq(Time.zone.parse("2026-09-05"))
      expect(result.rows).to be_empty
    end
  end

  context "with pagination" do
    let(:limit) { 1 }
    let(:offset) { 1 }

    it "returns the requested page with the totals of the whole level" do
      expect(summary(result.rows)).to eq([["data", 100_000, 1]])
      expect(result.groups_count).to eq(3)
      expect(result.total_amount_cents).to eq(180_200)
    end
  end

  context "with selected charges" do
    let(:charges) { [tokens_charge] }

    it "only reads the events of the selected charges" do
      expect(summary(result.rows)).to eq([[nil, 5_000, 1], ["data", 100_000, 1], ["eng", 75_000, 2]])
      expect(result.rows.flat_map(&:cells).map(&:charge_id).uniq).to eq([tokens_charge.id])
    end
  end

  context "with invalid selected charges" do
    let(:max_charge) { create(:standard_charge, plan:, billable_metric: create(:max_billable_metric, organization:)) }
    let(:charges) { [max_charge] }
    let(:split_charge) { tokens_charge }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(
        charges: ["unsupported_aggregation_type"],
        split_charge: %w[must_be_selected must_have_filters]
      )
    end
  end

  context "with an empty charges selection" do
    let(:charges) { [] }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(charges: ["must_not_be_empty"])
    end
  end

  context "with a selected charge outside the plan" do
    let(:charges) { [create(:standard_charge, organization:, billable_metric: tokens_metric)] }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("charge_not_found")
    end
  end

  context "with charge filters" do
    let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "model", values: %w[opus sonnet]) }
    let(:charge_filter) { create(:charge_filter, charge: tokens_charge, properties: {"amount" => "1"}) }

    before { create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["opus"]) }

    it "prices each event with its matching filter" do
      expect(summary(result.rows)).to eq([[nil, 5_000, 1], ["data", 200_000, 1], ["eng", 125_200, 3]])
    end

    context "when the charge is split" do
      let(:split_charge) { tokens_charge }

      it "returns one cell per filter and one for the default bucket" do
        expect(cells_of(result.rows.last)).to eq(
          [
            [requests_charge.id, nil, 1, 200, 1],
            [tokens_charge.id, nil, 500, 25_000, 1],
            [tokens_charge.id, charge_filter.id, 1000, 100_000, 1]
          ]
        )
      end
    end
  end

  context "with a charge priced in a pricing unit" do
    before { create(:applied_pricing_unit, organization:, pricing_unitable: tokens_charge, conversion_rate: 2) }

    it "converts the amount to the plan currency" do
      expect(summary(result.rows)).to eq([[nil, 10_000, 1], ["data", 200_000, 1], ["eng", 150_200, 3]])
    end
  end

  context "with a non linear charge" do
    let(:tokens_charge) { create(:graduated_charge, plan:, billable_metric: tokens_metric) }

    it "returns the units without an amount" do
      expect(summary(result.rows)).to eq([[nil, 0, 1], ["eng", 200, 3], ["data", 0, 1]])
      expect(cells_of(result.rows.second)).to eq(
        [
          [requests_charge.id, nil, 1, 200, 1],
          [tokens_charge.id, nil, 1500, nil, 2]
        ]
      )
    end
  end

  context "with a charge on an unsupported aggregation" do
    let(:requests_metric) { create(:max_billable_metric, organization:, code: "requests", field_name: "requests") }

    it "leaves the charge out" do
      expect(result.rows.flat_map(&:cells).map(&:charge_id).uniq).to eq([tokens_charge.id])
    end
  end

  context "without any supported charge" do
    let(:tokens_metric) { create(:max_billable_metric, organization:, code: "tokens", field_name: "tokens") }
    let(:requests_metric) { create(:max_billable_metric, organization:, code: "requests", field_name: "requests") }

    it "returns no rows" do
      expect(result).to be_success
      expect(result.rows).to eq([])
      expect(result.groups_count).to eq(0)
    end
  end

  context "with deduplication enabled" do
    let(:organization) do
      create(:organization, clickhouse_events_store: true, clickhouse_deduplication_enabled: true, feature_flags: ["account_tree"])
    end

    before do
      create_event(code: "tokens", value: 50, labels: {"team" => "ops"}, transaction_id: "tr_dup")
      create_event(code: "tokens", value: 50, labels: {"team" => "ops"}, transaction_id: "tr_dup")
    end

    it "counts duplicated events once" do
      expect(result.rows.find { it.value == "ops" }.events_count).to eq(1)
    end
  end

  context "when the query exceeds the groups limit" do
    before { stub_const("#{described_class}::MAX_GROUPS", 1) }

    it "returns a service failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("too_many_groups")
    end
  end

  context "when the feature flag is disabled" do
    let(:organization) { create(:organization, clickhouse_events_store: true) }

    it "returns a forbidden failure" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when the organization does not use the clickhouse events store" do
    let(:organization) { create(:organization, feature_flags: ["account_tree"]) }

    it "returns a forbidden failure" do
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "without subscription" do
    subject(:result) { described_class.call(subscription: nil, group_by:) }

    before { subscription }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("subscription_not_found")
    end
  end

  context "with a pending subscription" do
    let(:subscription) { create(:subscription, :pending, customer:, plan:) }

    it "returns a not allowed failure" do
      expect(result.error.code).to eq("subscription_not_started")
    end
  end

  context "with an unknown group_by type" do
    let(:group_by) { "department" }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("usage_attribution_type_not_found")
    end
  end

  context "with an unknown filter type" do
    let(:filters) { {"department" => "rnd"} }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("usage_attribution_type_not_found")
    end
  end

  context "with a split charge outside the plan" do
    let(:split_charge) { create(:standard_charge, organization:, billable_metric: tokens_metric) }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("charge_not_found")
    end
  end

  context "with invalid parameters" do
    let(:filters) { {"team" => Array.new(21) { "team-#{it}" }, "model" => []} }
    let(:from_datetime) { Time.zone.parse("2026-09-01") }
    let(:to_datetime) { Time.zone.parse("2026-10-15") }
    let(:split_charge) { requests_charge }
    let(:limit) { 101 }
    let(:offset) { -1 }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(
        filters: %w[values_are_required too_many_values],
        to_datetime: ["window_too_long"],
        limit: ["value_is_out_of_range"],
        offset: ["value_is_out_of_range"],
        split_charge: ["must_have_filters"]
      )
    end
  end

  context "with too many flat filters" do
    let(:filters) { %w[model api_key endpoint agent].index_with { "value" } }

    before { %w[api_key endpoint agent].each { create(:flat_usage_attribution_type, organization:, code: it) } }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(filters: ["too_many_flat_filters"])
    end
  end

  context "with an inverted window" do
    let(:from_datetime) { Time.zone.parse("2026-09-10") }
    let(:to_datetime) { Time.zone.parse("2026-09-01") }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(to_datetime: ["invalid_date_range"])
    end
  end

  context "with a single window boundary" do
    let(:from_datetime) { Time.zone.parse("2026-09-10") }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(to_datetime: ["both_boundaries_are_required"])
    end
  end
end
