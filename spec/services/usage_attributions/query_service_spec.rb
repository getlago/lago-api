# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributions::QueryService, clickhouse: {clean_before: true} do
  subject(:result) do
    described_class.call(
      subscription:, group_by:, filters:, from_datetime:, to_datetime:, charges:, split_charge:, search:, basis:, order_by:, limit:, offset:
    )
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
  let(:search) { nil }
  let(:basis) { "amount" }
  let(:order_by) { nil }
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
    row.cells.sort_by(&:units).map { [it.charge.id, it.charge_filter&.id, it.units, it.amount_cents, it.events_count] }
  end

  before do
    create(:usage_attribution_type, organization:, code: "team")
    create(:usage_attribution_type, organization:, code: "user")
    create(:flat_usage_attribution_type, organization:, code: "model")
    tokens_charge
    requests_charge
    events.each { create_event(**it) }
  end

  it "aggregates the current period per node, ranked by amount, with the unattributed usage apart" do
    expect(result).to be_success
    expect(summary(result.rows)).to eq([["data", 100_000, 1], ["eng", 75_200, 3]])
    expect(result.rows.map(&:rank)).to eq([1, 2])
    expect(result.unattributed).to have_attributes(amount_cents: 5_000, events_count: 1)
    expect(result.groups_count).to eq(2)
    expect(result.totals).to have_attributes(amount_cents: 180_200, events_count: 5)
    expect(result.basis).to eq("amount")
    expect(result.from_datetime).to eq(Time.zone.parse("2026-09-01"))
    expect(result.to_datetime).to eq(Time.zone.parse("2026-09-30").end_of_day)
    expect(result.currency).to eq("EUR")
    expect(result).to have_attributes(subscription:, group_by: "team", limit: 50, offset: 0)
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
      expect(result.unattributed).to have_attributes(amount_cents: 0, events_count: 0)
    end
  end

  context "with a filter on unattributed usage" do
    let(:group_by) { "user" }
    let(:filters) { {"team" => nil} }

    it "matches the events without the label" do
      expect(result.rows).to eq([])
      expect(result.unattributed).to have_attributes(amount_cents: 5_000, events_count: 1)
      expect(result.totals).to have_attributes(amount_cents: 5_000, events_count: 1)
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

  context "with a yearly plan" do
    let(:plan) { create(:plan, organization:, interval: :yearly, amount_currency: "EUR") }

    it "narrows the current period to its last 31 days" do
      expect(result.from_datetime).to eq(Time.zone.parse("2026-08-15 12:00:00"))
      expect(result.to_datetime).to eq(Time.zone.parse("2026-09-15 12:00:00"))
      expect(summary(result.rows)).to eq([["eng", 125_150, 4], ["data", 100_000, 1]])
    end
  end

  context "with pagination" do
    let(:limit) { 1 }
    let(:offset) { 1 }

    it "returns the requested page with the totals of the whole level" do
      expect(summary(result.rows)).to eq([["eng", 75_200, 3]])
      expect(result.groups_count).to eq(2)
      expect(result.totals).to have_attributes(amount_cents: 180_200, events_count: 5)
      expect(result).to have_attributes(limit: 1, offset: 1)
    end

    context "when on the first page" do
      let(:offset) { 0 }

      it "returns the first ranked value with the totals of the whole level" do
        expect(summary(result.rows)).to eq([["data", 100_000, 1]])
        expect(result.totals).to have_attributes(amount_cents: 180_200, events_count: 5)
      end
    end
  end

  context "with the default basis" do
    subject(:result) { described_class.call(subscription:, group_by:) }

    let(:model_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "model", values: %w[opus sonnet]) }

    before do
      create(:charge_filter_value, charge_filter: create(:charge_filter, charge: tokens_charge), billable_metric_filter: model_filter, values: ["opus"])
      allow(UsageAttributions::ChargePriceLookupService).to receive(:call!).and_call_original
    end

    it "returns the units ranked by events, without amounts" do
      expect(result.basis).to eq("units")
      expect(summary(result.rows)).to eq([["eng", nil, 3], ["data", nil, 1]])
      expect(cells_of(result.rows.first)).to eq(
        [
          [requests_charge.id, nil, 1, nil, 1],
          [tokens_charge.id, nil, 1500, nil, 2]
        ]
      )
      expect(result.totals).to have_attributes(amount_cents: nil, events_count: 5)
    end

    it "does not match the events with the charge filters" do
      result
      expect(UsageAttributions::ChargePriceLookupService).not_to have_received(:call!)
    end

    context "with a split charge" do
      subject(:result) { described_class.call(subscription:, group_by:, split_charge: tokens_charge) }

      it "returns the units of each filter" do
        expect(cells_of(result.rows.first)).to eq(
          [
            [requests_charge.id, nil, 1, nil, 1],
            [tokens_charge.id, nil, 500, nil, 1],
            [tokens_charge.id, tokens_charge.filters.first.id, 1000, nil, 1]
          ]
        )
      end
    end

    context "when ordered by amount" do
      subject(:result) { described_class.call(subscription:, group_by:, order_by: "amount") }

      it "returns a validation failure" do
        expect(result.error.messages).to eq(order_by: ["requires_amount_basis"])
      end
    end
  end

  context "with a hierarchical level under a parent type" do
    let(:department_type) { create(:usage_attribution_type, organization:, code: "department") }
    let(:group_by) { "squad" }

    before { create(:usage_attribution_type, organization:, code: "squad", parent: department_type) }

    it "returns a validation failure without a filter on the parent" do
      expect(result.error.messages).to eq(group_by: ["parent_filter_required"])
    end

    context "with a filter on the parent" do
      let(:filters) { {"department" => "rnd"} }

      it "reads the level" do
        expect(result).to be_success
      end
    end

    context "with a filter on the unattributed parent" do
      let(:filters) { {"department" => nil} }

      it "reads the level" do
        expect(result).to be_success
      end
    end

    context "when the parent type is deleted" do
      let(:department_type) { create(:usage_attribution_type, organization:, code: "department", deleted_at: Time.current) }

      it "reads the level as a top level" do
        expect(result).to be_success
      end
    end
  end

  context "with a search" do
    let(:search) { "EN" }

    it "returns the matching values with their rank in the level" do
      expect(result.rows.map { [it.value, it.rank] }).to eq([["eng", 2]])
      expect(result.groups_count).to eq(2)
    end
  end

  context "when ordered by events count" do
    let(:order_by) { "events_count" }

    it "ranks the values by their events" do
      expect(summary(result.rows)).to eq([["eng", 75_200, 3], ["data", 100_000, 1]])
    end
  end

  context "with selected charges" do
    let(:charges) { [tokens_charge] }

    it "only reads the events of the selected charges" do
      expect(summary(result.rows)).to eq([["data", 100_000, 1], ["eng", 75_000, 2]])
      expect(result.unattributed).to have_attributes(amount_cents: 5_000, events_count: 1)
      expect(result.rows.flat_map(&:cells).map { it.charge.id }.uniq).to eq([tokens_charge.id])
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
      expect(summary(result.rows)).to eq([["data", 200_000, 1], ["eng", 125_200, 3]])
    end

    context "with a more specific filter" do
      let(:region_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "region", values: %w[eu us]) }
      let(:opus_eu_filter) { create(:charge_filter, charge: tokens_charge, properties: {"amount" => "3"}) }

      before do
        create(:charge_filter_value, charge_filter: opus_eu_filter, billable_metric_filter:, values: ["opus"])
        create(:charge_filter_value, charge_filter: opus_eu_filter, billable_metric_filter: region_filter, values: ["eu"])
        create_event(code: "tokens", value: 10, labels: {"team" => "eng"}, properties: {"model" => "opus", "region" => "eu"})
      end

      it "prices the events matching it with its amount" do
        expect(summary(result.rows)).to eq([["data", 200_000, 1], ["eng", 128_200, 4]])
      end

      context "when the charge is split" do
        let(:split_charge) { tokens_charge }

        it "lists the filters in their order, the default last" do
          expect(result.totals.cells.select { it.charge == tokens_charge }.map(&:charge_filter)).to eq([charge_filter, opus_eu_filter, nil])
        end
      end
    end

    context "when the price lookup is too large" do
      before { stub_const("UsageAttributions::ChargePriceLookupService::MAX_ENTRIES", 0) }

      it "returns the charge in units only" do
        expect(summary(result.rows)).to eq([["eng", 200, 3], ["data", 0, 1]])
        expect(cells_of(result.rows.first)).to eq(
          [
            [requests_charge.id, nil, 1, 200, 1],
            [tokens_charge.id, nil, 1500, nil, 2]
          ]
        )
      end
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
      expect(summary(result.rows)).to eq([["data", 200_000, 1], ["eng", 150_200, 3]])
      expect(result.unattributed).to have_attributes(amount_cents: 10_000, events_count: 1)
    end
  end

  context "with a non linear charge" do
    let(:tokens_charge) { create(:graduated_charge, plan:, billable_metric: tokens_metric) }

    it "returns the units without an amount" do
      expect(summary(result.rows)).to eq([["eng", 200, 3], ["data", 0, 1]])
      expect(cells_of(result.rows.first)).to eq(
        [
          [requests_charge.id, nil, 1, 200, 1],
          [tokens_charge.id, nil, 1500, nil, 2]
        ]
      )
    end
  end

  context "with thousands of charge filters" do
    let(:model_filter) { create(:billable_metric_filter, billable_metric: tokens_metric, key: "model", values: %w[opus sonnet]) }

    # rubocop:disable Rails/SkipsModelValidations
    before do
      now = Time.current
      filter_ids = ChargeFilter.insert_all!(
        Array.new(3_000) { {charge_id: tokens_charge.id, organization_id: organization.id, properties: {"amount" => "0.1"}, created_at: now, updated_at: now} },
        returning: :id
      ).rows.flatten
      ChargeFilterValue.insert_all!(
        filter_ids.each_with_index.map do |filter_id, index|
          {
            charge_filter_id: filter_id,
            billable_metric_filter_id: model_filter.id,
            organization_id: organization.id,
            values: [index.zero? ? "opus" : "model-#{index}"],
            created_at: now,
            updated_at: now
          }
        end
      )
    end
    # rubocop:enable Rails/SkipsModelValidations

    it "prices each event with its filter" do
      expect(summary(result.rows)).to eq([["eng", 35_200, 3], ["data", 20_000, 1]])
      expect(result.unattributed).to have_attributes(amount_cents: 5_000, events_count: 1)
    end
  end

  context "with a charge on an unsupported aggregation" do
    let(:requests_metric) { create(:max_billable_metric, organization:, code: "requests", field_name: "requests") }

    it "leaves the charge out" do
      expect(result.rows.flat_map(&:cells).map { it.charge.id }.uniq).to eq([tokens_charge.id])
    end
  end

  context "without any supported charge" do
    let(:tokens_metric) { create(:max_billable_metric, organization:, code: "tokens", field_name: "tokens") }
    let(:requests_metric) { create(:max_billable_metric, organization:, code: "requests", field_name: "requests") }

    it "returns no rows" do
      expect(result).to be_success
      expect(result.rows).to eq([])
      expect(result.groups_count).to eq(0)
      expect(result.totals).to have_attributes(amount_cents: 0, events_count: 0)
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

  context "with a terminated subscription" do
    let(:subscription) do
      create(:subscription, :calendar, customer:, plan:, started_at:, subscription_at: started_at,
        status: :terminated, terminated_at: Time.zone.parse("2026-09-05"))
    end

    it "returns a not allowed failure" do
      expect(result.error.code).to eq("subscription_not_active")
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

  context "with a split charge holding too many filters" do
    let(:split_charge) { tokens_charge }

    before { create_list(:charge_filter, 11, charge: tokens_charge) }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(split_charge: ["too_many_filters"])
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
    let(:search) { "a" * 101 }
    let(:basis) { "euros" }
    let(:order_by) { "units" }
    let(:limit) { 101 }
    let(:offset) { -1 }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(
        filters: %w[values_are_required too_many_values],
        to_datetime: ["window_too_long"],
        limit: ["value_is_out_of_range"],
        offset: ["value_is_out_of_range"],
        search: ["value_is_too_long"],
        basis: ["value_is_invalid"],
        order_by: ["value_is_invalid"],
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

  context "with a window ending before the subscription start" do
    let(:from_datetime) { Time.zone.parse("2026-07-01") }
    let(:to_datetime) { Time.zone.parse("2026-07-20") }

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
