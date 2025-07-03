# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::UsageSerializer do
  subject(:serializer) { described_class.new(usage, root_name: "customer_usage", includes: [:charges_usage]) }

  let(:fixed_date) { Date.new(2025, 7, 2) }
  let(:from_datetime) { fixed_date.beginning_of_month }
  let(:to_datetime) { fixed_date.end_of_month }
  let(:issuing_date) { fixed_date.end_of_month }
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
          billable_metric: OpenStruct.new(
            id: SecureRandom.uuid,
            name: "Charge",
            code: "charge",
            aggregation_type: "count_agg",
            recurring: false
          ),
          charge: OpenStruct.new(
            id: SecureRandom.uuid,
            charge_model: "graduated",
            charge_id: SecureRandom.uuid,
            invoice_display_name: "Test Charge",
            filters: [],
            billable_metric: OpenStruct.new(recurring: false)
          ),
          charge_id: SecureRandom.uuid,
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
  let(:result) { JSON.parse(serializer.to_json) }

  before do
    allow(Date).to receive(:current).and_return(fixed_date)
    allow(Time).to receive(:current).and_return(fixed_date.to_time)
  end

  it "serializes the customer usage" do
    aggregate_failures do
      expect(result["customer_usage"]["from_datetime"]).to eq(from_datetime.iso8601)
      expect(result["customer_usage"]["to_datetime"]).to eq(to_datetime.iso8601)
      expect(result["customer_usage"]["issuing_date"]).to eq(issuing_date.iso8601)
      expect(result["customer_usage"]["currency"]).to eq("EUR")
      expect(result["customer_usage"]["taxes_amount_cents"]).to eq(1)
      expect(result["customer_usage"]["amount_cents"]).to eq(5)
      expect(result["customer_usage"]["total_amount_cents"]).to eq(6)

      charge_usage = result["customer_usage"]["charges_usage"].first
      expect(charge_usage["billable_metric"]["name"]).to eq("Charge")
      expect(charge_usage["billable_metric"]["code"]).to eq("charge")
      expect(charge_usage["billable_metric"]["aggregation_type"]).to eq("count_agg")
      expect(charge_usage["charge"]["charge_model"]).to eq("graduated")
      expect(charge_usage["units"]).to eq("4.0")
      expect(charge_usage["projected_units"]).to eq("60.0")
      expect(charge_usage["amount_cents"]).to eq(5)
      expect(charge_usage["projected_amount_cents"]).to eq(75)
      expect(charge_usage["amount_currency"]).to eq("EUR")
    end
  end
end
