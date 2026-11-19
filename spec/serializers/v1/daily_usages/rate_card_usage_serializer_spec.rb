# frozen_string_literal: true

require "rails_helper"

RSpec.describe V1::DailyUsages::RateCardUsageSerializer do
  subject(:payload) { described_class.new(usage).serialize }

  let(:usage) { RateCardUsage.new(contract_rate_card:, billing_segment:, rate_phase: nil, fees:) }
  let(:customer) { build_stubbed(:customer, timezone: "UTC") }
  let(:billable_metric) { build_stubbed(:billable_metric, code: "api_calls", name: "API calls", aggregation_type: "sum_agg") }
  let(:product) { build_stubbed(:product, billable_metric:, code: "api") }
  let(:billable_metric_filter) do
    build_stubbed(:billable_metric_filter, billable_metric:, key: "region", values: %w[eu-west eu-east us])
  end
  let(:product_filter) do
    build(:product_filter, id: SecureRandom.uuid, product:, code: "eu").tap do |filter|
      filter.values = %w[eu-west eu-east].map do |value|
        build(:product_filter_value, product_filter: filter, billable_metric_filter:, value:)
      end
    end
  end
  let(:rate_card) { build_stubbed(:rate_card, product:, product_filter:, code: "api_monthly") }
  let(:contract_rate_card) { build_stubbed(:contract_rate_card, rate_card:) }
  let(:billing_segment) do
    build_stubbed(
      :billing_segment,
      customer:,
      contract_rate_card:,
      rate_card_rate: build_stubbed(:rate_card_rate, rate_card:, rate_model: "standard"),
      currency: "EUR",
      started_at: Time.zone.parse("2027-02-01T00:00:00Z"),
      ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01T00:00:00Z")),
      billing_at: Time.zone.parse("2027-03-01T00:00:00Z")
    )
  end
  let(:fees) do
    [
      build_stubbed(:fee, units: BigDecimal("2.5"), total_aggregated_units: BigDecimal("2.5"), events_count: 3,
        amount_cents: 500, taxes_amount_cents: 0, grouped_by: {"region" => "eu-west"}),
      build_stubbed(:fee, units: BigDecimal(1), total_aggregated_units: BigDecimal(1), events_count: 1,
        amount_cents: 200, taxes_amount_cents: 0, grouped_by: {"region" => "eu-east"})
    ]
  end

  it "serializes the usage with one entry named by its rate card and product" do
    expect(payload).to eq(
      from_datetime: Time.zone.parse("2027-02-01T00:00:00Z"),
      to_datetime: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01T00:00:00Z")),
      issuing_date: "2027-03-01",
      currency: "EUR",
      amount_cents: 700, # 500 + 200
      total_amount_cents: 700,
      taxes_amount_cents: 0,
      lago_invoice_id: nil,
      charges_usage: [
        {
          units: "3.5", # 2.5 + 1
          total_aggregated_units: "3.5",
          events_count: 4,
          amount_cents: 700,
          pricing_unit_details: nil,
          amount_currency: "EUR",
          contract_rate_card: {lago_id: contract_rate_card.id},
          rate_card: {lago_id: rate_card.id, code: "api_monthly", rate_model: "standard"},
          product: {lago_id: product.id, code: "api"},
          product_filter: {lago_id: product_filter.id, code: "eu", values: {"region" => %w[eu-west eu-east]}},
          billable_metric: {lago_id: billable_metric.id, name: "API calls", code: "api_calls", aggregation_type: "sum_agg"},
          filters: [],
          grouped_usage: [
            {
              units: "2.5",
              total_aggregated_units: "2.5",
              events_count: 3,
              amount_cents: 500,
              pricing_unit_details: nil,
              grouped_by: {"region" => "eu-west"},
              filters: []
            },
            {
              units: "1.0",
              total_aggregated_units: "1.0",
              events_count: 1,
              amount_cents: 200,
              pricing_unit_details: nil,
              grouped_by: {"region" => "eu-east"},
              filters: []
            }
          ]
        }
      ]
    )
  end
end
