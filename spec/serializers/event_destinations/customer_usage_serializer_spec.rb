# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsageSerializer do
  subject(:result) { described_class.new(usage, root_name: "customer_usage", wallets:).serialize }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "api_calls") }
  let(:wallet) do
    create(:wallet, customer:, organization:, rate_amount: "1.0", currency: "EUR",
      ongoing_usage_balance_cents: 1500, credits_ongoing_usage_balance: "15.0")
  end
  let(:wallets) { [wallet] }
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

  describe "charges with no usage" do
    let(:unused_charge) { create(:standard_charge, plan:, billable_metric: create(:billable_metric, organization:, code: "unused")) }

    it "omits a charge with neither units nor amount" do
      usage.fees << build(:charge_fee, charge: unused_charge, subscription:, units: "0.0", events_count: 0,
        amount_cents: 0, amount_currency: "EUR", charge_filter: nil, grouped_by: {})

      expect(result[:charges_usage].map { it[:charge][:code] }).to eq([charge.code])
    end

    it "keeps a charge billed without units, which is real usage" do
      usage.fees << build(:charge_fee, charge: unused_charge, subscription:, units: "0.0", events_count: 0,
        amount_cents: 250, amount_currency: "EUR", charge_filter: nil, grouped_by: {})

      expect(result[:charges_usage].map { it[:charge][:code] }).to match_array([charge.code, unused_charge.code])
    end

    it "keeps a charge with units but nothing to pay, such as a free allowance" do
      usage.fees << build(:charge_fee, charge: unused_charge, subscription:, units: "3.0", events_count: 3,
        amount_cents: 0, amount_currency: "EUR", charge_filter: nil, grouped_by: {})

      expect(result[:charges_usage].map { it[:charge][:code] }).to match_array([charge.code, unused_charge.code])
    end
  end

  it "leaks no per-filter breakdown" do
    expect(result[:charges_usage].first.keys).not_to include(:filters, :grouped_usage, :presentation_breakdowns)
  end

  describe "datetime formatting" do
    it "passes strings through untouched" do
      expect(result[:from_datetime]).to eq("2026-09-01T00:00:00Z")
      expect(result[:issuing_date]).to eq("2026-09-30")
    end

    context "when the usage carries time objects instead of strings" do
      let(:usage) do
        SubscriptionUsage.new(
          from_datetime: Time.utc(2026, 9, 1).in_time_zone("UTC"),
          to_datetime: Time.utc(2026, 9, 30, 23, 59, 59).in_time_zone("UTC"),
          issuing_date: Date.new(2026, 9, 30),
          currency: "EUR",
          amount_cents: 1500,
          total_amount_cents: 1500,
          taxes_amount_cents: 0,
          fees: []
        )
      end

      it "formats them, so the wire shape does not depend on what the caller passed" do
        expect(result[:from_datetime]).to eq("2026-09-01T00:00:00Z")
        expect(result[:to_datetime]).to eq("2026-09-30T23:59:59Z")
        expect(result[:issuing_date]).to eq("2026-09-30")
      end
    end
  end

  it "carries no taxes, since usage is computed without them" do
    expect(result.keys).not_to include(:taxes_amount_cents, :total_amount_cents)
  end

  describe "wallets" do
    it "reports the ongoing usage the refresh allocated to the wallet" do
      expect(result[:wallets]).to eq(
        [{lago_id: wallet.id, credits: "15.0", amount_cents: 1500, amount_currency: "EUR"}]
      )
    end

    it "no longer carries a single wallet id, which could not express a split" do
      expect(result.keys).not_to include(:wallet_id, :credits)
    end

    context "when the customer has several wallets" do
      let(:other) do
        create(:wallet, customer:, organization:, rate_amount: "1.0", currency: "EUR",
          ongoing_usage_balance_cents: 500, credits_ongoing_usage_balance: "5.0")
      end
      let(:wallets) { [wallet, other] }

      it "reports each wallet's own share rather than picking one" do
        expect(result[:wallets].map { it[:amount_cents] }).to eq([1500, 500])
        expect(result[:wallets].map { it[:lago_id] }).to eq([wallet.id, other.id])
      end
    end

    context "when a wallet is in another currency" do
      let(:other) do
        create(:wallet, customer:, organization:, rate_amount: "1.0", currency: "USD",
          ongoing_usage_balance_cents: 200, credits_ongoing_usage_balance: "2.0")
      end
      let(:wallets) { [wallet, other] }

      it "names each wallet's own currency, so the figures are not ambiguous" do
        expect(result[:wallets].map { it[:amount_currency] }).to eq(%w[EUR USD])
      end
    end

    context "when the customer has no wallet" do
      let(:wallets) { [] }

      it "sends an empty list rather than omitting the field" do
        expect(result[:wallets]).to eq([])
        expect(result[:amount_cents]).to eq(1500)
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
