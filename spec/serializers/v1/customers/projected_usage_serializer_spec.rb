# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::ProjectedUsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: "customer_projected_usage") }

  let(:fixed_date) { Date.new(2025, 7, 2) }
  let(:result) { JSON.parse(serializer.to_json) }
  let(:from_datetime) { fixed_date.beginning_of_month }
  let(:to_datetime) { fixed_date.end_of_month }
  let(:issuing_date) { fixed_date.end_of_month }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:plan) { create(:plan, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer, plan: plan) }
  let(:billable_metric) { create(:billable_metric, organization: organization) }
  let(:charge) { create(:standard_charge, plan: plan, billable_metric: billable_metric) }

  let(:usage) do
    SubscriptionUsage.new(
      from_datetime: from_datetime.iso8601,
      to_datetime: to_datetime.iso8601,
      issuing_date: issuing_date.iso8601,
      amount_cents: 5,
      currency: "EUR",
      total_amount_cents: 6,
      taxes_amount_cents: 1,
      fees: [
        OpenStruct.new(
          billable_metric: billable_metric,
          charge: charge,
          charge_id: charge.id,
          subscription: subscription,
          units: "4.0",
          amount_cents: 5,
          amount_currency: "EUR",
          events_count: 1,
          charge_filter: nil,
          grouped_by: {},
          properties: {
            "from_datetime" => from_datetime.iso8601,
            "to_datetime" => to_datetime.iso8601,
            "charges_duration" => 30
          }
        )
      ]
    )
  end

  before do
    allow(Date).to receive(:current).and_return(fixed_date)
    allow(Time).to receive(:current).and_return(fixed_date.to_time)

    projection_result = instance_double(
      "Fees::ProjectionService::Result",
      projected_units: BigDecimal("60.0"),
      projected_amount_cents: 75,
      projected_pricing_unit_amount_cents: BigDecimal("0")
    )

    allow(::Fees::ProjectionService).to receive(:call).and_return(
      instance_double("BaseService::Result", raise_if_error!: projection_result)
    )
  end

  it "serializes the projected customer usage" do
    aggregate_failures do
      expect(result["customer_projected_usage"]["from_datetime"]).to eq(from_datetime.iso8601)
      expect(result["customer_projected_usage"]["to_datetime"]).to eq(to_datetime.iso8601)
      expect(result["customer_projected_usage"]["issuing_date"]).to eq(issuing_date.iso8601)
      expect(result["customer_projected_usage"]["currency"]).to eq("EUR")
      expect(result["customer_projected_usage"]["taxes_amount_cents"]).to eq(1)
      expect(result["customer_projected_usage"]["amount_cents"]).to eq(5)
      expect(result["customer_projected_usage"]["total_amount_cents"]).to eq(6)
      expect(result["customer_projected_usage"]["projected_amount_cents"]).to eq(75)

      charge_usage = result["customer_projected_usage"]["charges_usage"].first
      expect(charge_usage["billable_metric"]["name"]).to eq(billable_metric.name)
      expect(charge_usage["billable_metric"]["code"]).to eq(billable_metric.code)
      expect(charge_usage["billable_metric"]["aggregation_type"]).to eq(billable_metric.aggregation_type)
      expect(charge_usage["charge"]["charge_model"]).to eq(charge.charge_model)
      expect(charge_usage["units"]).to eq("4.0")
      expect(charge_usage["projected_units"]).to eq("60.0")
      expect(charge_usage["amount_cents"]).to eq(5)
      expect(charge_usage["projected_amount_cents"]).to eq(75)
      expect(charge_usage["amount_currency"]).to eq("EUR")
    end
  end
end
