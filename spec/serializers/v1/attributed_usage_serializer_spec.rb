# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::AttributedUsageSerializer do
  subject(:serializer) do
    described_class.new(query_result, root_name: "attributed_usage")
  end

  let(:result) { JSON.parse(serializer.to_json)["attributed_usage"] }

  let(:subscription) { create(:subscription) }
  let(:billable_metric) { create(:sum_billable_metric, organization: subscription.organization, code: "tokens") }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, code: "tokens_charge") }
  let(:billable_metric_filter) { create(:billable_metric_filter, billable_metric:, key: "model", values: %w[opus sonnet]) }
  let(:charge_filter) { create(:charge_filter, charge:, invoice_display_name: "Opus") }

  let(:basis) { "amount" }
  let(:filter_amount_cents) { "50000.5" }
  let(:default_amount_cents) { "25000" }
  let(:total_amount_cents) { "75000.5" }
  let(:unattributed_amount_cents) { "0" }

  let(:filter_cell) { cell(charge_filter:, units: "1000", amount_cents: filter_amount_cents, events_count: 2) }
  let(:default_cell) { cell(charge_filter: nil, units: "500", amount_cents: default_amount_cents, events_count: 1) }
  let(:empty_cell) { cell(charge_filter: nil, units: "0", amount_cents: unattributed_amount_cents, events_count: 0) }

  let(:query_result) do
    UsageAttributions::QueryService::Result.new.tap do |result|
      result.subscription = subscription
      result.group_by = "team"
      result.rows = [
        UsageAttributions::QueryService::Row.new(
          value: "eng", rank: 1, amount_cents: decimal(total_amount_cents), events_count: 3, cells: [filter_cell, default_cell]
        )
      ]
      result.unattributed = aggregate(amount_cents: unattributed_amount_cents, events_count: 0, cells: [empty_cell])
      result.totals = aggregate(amount_cents: total_amount_cents, events_count: 3, cells: [filter_cell, default_cell])
      result.groups_count = 1
      result.basis = basis
      result.from_datetime = Time.zone.parse("2026-09-01")
      result.to_datetime = Time.zone.parse("2026-09-30").end_of_day
      result.currency = "EUR"
    end
  end

  def decimal(value)
    value && BigDecimal(value)
  end

  def cell(charge_filter:, units:, amount_cents:, events_count:)
    UsageAttributions::QueryService::Cell.new(
      charge:, charge_filter:, units: decimal(units), amount_cents: decimal(amount_cents), events_count:
    )
  end

  def aggregate(amount_cents:, events_count:, cells:)
    UsageAttributions::QueryService::Aggregate.new(amount_cents: decimal(amount_cents), events_count:, cells:)
  end

  before { create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ["opus"]) }

  it "serializes the level" do
    expect(result.except("rows", "unattributed", "totals")).to eq(
      "lago_subscription_id" => subscription.id,
      "external_subscription_id" => subscription.external_id,
      "group_by" => "team",
      "basis" => "amount",
      "from_datetime" => "2026-09-01T00:00:00Z",
      "to_datetime" => "2026-09-30T23:59:59Z",
      "currency" => "EUR"
    )
  end

  it "serializes the rows with their charges usage" do
    expect(result["rows"]).to eq(
      [
        {
          "value" => "eng",
          "rank" => 1,
          "amount_cents" => 75_001,
          "precise_amount_cents" => "75000.5",
          "events_count" => 3,
          "charges_usage" => [
            {
              "lago_charge_id" => charge.id,
              "charge_code" => "tokens_charge",
              "billable_metric_code" => "tokens",
              "lago_charge_filter_id" => charge_filter.id,
              "charge_filter_values" => {"model" => ["opus"]},
              "charge_filter_invoice_display_name" => "Opus",
              "units" => "1000.0",
              "amount_cents" => 50_001,
              "precise_amount_cents" => "50000.5",
              "events_count" => 2
            },
            {
              "lago_charge_id" => charge.id,
              "charge_code" => "tokens_charge",
              "billable_metric_code" => "tokens",
              "lago_charge_filter_id" => nil,
              "charge_filter_values" => nil,
              "charge_filter_invoice_display_name" => nil,
              "units" => "500.0",
              "amount_cents" => 25_000,
              "precise_amount_cents" => "25000.0",
              "events_count" => 1
            }
          ]
        }
      ]
    )
  end

  it "serializes the unattributed usage and the totals" do
    expect(result["unattributed"]).to include("amount_cents" => 0, "precise_amount_cents" => "0.0", "events_count" => 0)
    expect(result["unattributed"]["charges_usage"].pluck("units")).to eq(["0.0"])
    expect(result["totals"]).to include("amount_cents" => 75_001, "precise_amount_cents" => "75000.5", "events_count" => 3)
    expect(result["totals"]["charges_usage"].pluck("lago_charge_filter_id")).to eq([charge_filter.id, nil])
  end

  context "with the units basis" do
    let(:basis) { "units" }
    let(:filter_amount_cents) { nil }
    let(:default_amount_cents) { nil }
    let(:total_amount_cents) { nil }
    let(:unattributed_amount_cents) { nil }

    it "serializes the amounts as null" do
      row = result["rows"].first

      expect(row.slice("amount_cents", "precise_amount_cents")).to eq("amount_cents" => nil, "precise_amount_cents" => nil)
      expect(row["charges_usage"].map { it.slice("units", "amount_cents", "precise_amount_cents") }).to eq(
        [
          {"units" => "1000.0", "amount_cents" => nil, "precise_amount_cents" => nil},
          {"units" => "500.0", "amount_cents" => nil, "precise_amount_cents" => nil}
        ]
      )
      expect(result["totals"]).to include("amount_cents" => nil, "events_count" => 3)
    end
  end
end
