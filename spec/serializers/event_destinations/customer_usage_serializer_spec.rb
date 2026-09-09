# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsageSerializer do
  subject(:result) { described_class.new(usage, root_name: "customer_usage", wallet:).serialize }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:wallet) { create(:wallet, customer:, organization:, rate_amount: "1.0", currency: "EUR") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:usage) do
    SubscriptionUsage.new(
      from_datetime: "2026-09-01T00:00:00Z",
      to_datetime: "2026-09-30T23:59:59Z",
      issuing_date: "2026-09-30",
      currency: "EUR",
      amount_cents: 1500,
      total_amount_cents: 1500,
      taxes_amount_cents: 0,
      fees: [
        build(:charge_fee, charge:, subscription:, units: "10.0", events_count: 4, amount_cents: 1000, amount_currency: "EUR", charge_filter: nil, grouped_by: {}),
        build(:charge_fee, charge:, subscription:, units: "5.0", events_count: 2, amount_cents: 500, amount_currency: "EUR", charge_filter: nil, grouped_by: {})
      ]
    )
  end

  it "returns the aggregates and the identifiers" do
    expect(result[:currency]).to eq("EUR")
    expect(result[:amount_cents]).to eq(1500)
    expect(result[:charges_usage]).to eq(
      [
        {
          units: "15.0",
          events_count: 6,
          amount_cents: 1500,
          amount_currency: "EUR",
          charge: {lago_id: charge.id, code: charge.code},
          billable_metric: {lago_id: billable_metric.id, code: "api_calls"}
        }
      ]
    )
  end

  it "leaks no per-filter breakdown" do
    expect(result[:charges_usage].first.keys).not_to include(:filters, :grouped_usage, :presentation_breakdowns)
  end

  it "carries no taxes, since usage is computed without them" do
    expect(result.keys).not_to include(:taxes_amount_cents, :total_amount_cents)
  end

  describe "credits" do
    it "converts the amount through the wallet's rate" do
      expect(result[:credits]).to eq("15.0")
    end

    it "names the wallet the conversion went through" do
      expect(result[:wallet_id]).to eq(wallet.id)
    end

    context "when the rate is not one credit per unit of currency" do
      let(:wallet) { create(:wallet, customer:, organization:, rate_amount: "0.5", currency: "EUR") }

      it "divides by the rate" do
        expect(result[:credits]).to eq("30.0")
      end
    end

    context "when the customer has no wallet" do
      let(:wallet) { nil }

      it "sends no credits rather than an unconvertible figure" do
        expect(result[:credits]).to be_nil
        expect(result[:amount_cents]).to eq(1500)
      end

      it "sends a null wallet_id, so a null credits is not a mystery" do
        expect(result[:wallet_id]).to be_nil
      end
    end

    context "when the only wallet is in another currency" do
      let(:wallet) { nil }

      it "sends no credits, since that wallet cannot fund this usage" do
        create(:wallet, customer:, organization:, rate_amount: "1.0", currency: "USD")

        expect(result[:credits]).to be_nil
        expect(result[:currency]).to eq("EUR")
      end
    end

    context "when the rate is zero" do
      let(:wallet) { build(:wallet, customer:, organization:, rate_amount: "0.0", currency: "EUR") }

      it "sends no credits rather than dividing by zero" do
        expect(result[:credits]).to be_nil
      end
    end
  end
end
