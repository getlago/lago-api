# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::CustomerUsageSerializer do
  subject(:result) { described_class.new(usage, root_name: "customer_usage", wallets:, wallet_amounts:).serialize }

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
  let(:wallet_amounts) { {} }
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
          billable_metric: {lago_id: billable_metric.id, code: "api_calls"},
          wallet_id: nil
        }
      ]
    )
  end

  describe "usage per wallet" do
    let(:first_wallet_id) { "00000000-0000-4000-8000-000000000001" }
    let(:second_wallet_id) { "00000000-0000-4000-8000-000000000002" }
    let(:entries) { result[:charges_usage].map { it.slice(:wallet_id, :units, :events_count, :amount_cents) } }

    context "when one wallet absorbed the whole charge" do
      let(:wallet_amounts) { {billable_metric.id => {first_wallet_id => 1500}} }

      it "sends one entry for that wallet" do
        expect(entries).to eq([{wallet_id: first_wallet_id, units: "15.0", events_count: 6, amount_cents: 1500}])
      end
    end

    context "when two wallets share the charge" do
      let(:wallet_amounts) { {billable_metric.id => {second_wallet_id => 600, first_wallet_id => 1050}} }

      it "splits it in proportion, largest first, and the parts add up to the charge" do
        expect(entries).to eq([
          {wallet_id: first_wallet_id, units: "10.0", events_count: 4, amount_cents: 955},
          {wallet_id: second_wallet_id, units: "5.0", events_count: 2, amount_cents: 545}
        ])
      end
    end

    context "when wallets absorbed only part of the charge" do
      let(:wallet_amounts) { {billable_metric.id => {first_wallet_id => 1000}} }

      it "sends the rest without a wallet" do
        expect(entries).to eq([
          {wallet_id: first_wallet_id, units: "10.0", events_count: 4, amount_cents: 1000},
          {wallet_id: nil, units: "5.0", events_count: 2, amount_cents: 500}
        ])
      end
    end

    context "when whole units are shared by more wallets than there are units" do
      let(:wallet_ids) { Array.new(7) { "00000000-0000-4000-8000-00000000001#{it}" } }
      let(:wallet_amounts) { {billable_metric.id => wallet_ids.index_with { 300 }} }
      let(:usage) do
        SubscriptionUsage.new(
          from_datetime: "2026-09-01T00:00:00Z",
          to_datetime: "2026-09-30T23:59:59Z",
          issuing_date: "2026-09-30",
          currency: "EUR",
          amount_cents: 1500,
          total_amount_cents: 1500,
          taxes_amount_cents: 0,
          fees: [build(:charge_fee, charge:, subscription:, units: "5", events_count: 5, amount_cents: 1500, amount_currency: "EUR", charge_filter: nil, grouped_by: {})]
        )
      end

      it "never sends negative units, and the parts still add up" do
        units = entries.map { BigDecimal(it[:units]) }

        expect(units).to all(be >= 0)
        expect(units.sum).to eq(5)
      end
    end

    context "when two charges share the billable metric" do
      let(:other_charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:wallet_amounts) { {billable_metric.id => {first_wallet_id => 1500}} }

      before do
        usage.fees << build(:charge_fee, charge: other_charge, subscription:, units: "15.0", events_count: 6,
          amount_cents: 1500, amount_currency: "EUR", charge_filter: nil, grouped_by: {})
      end

      it "counts the wallet's money once across both charges" do
        wallet_entries = result[:charges_usage].select { it[:wallet_id] == first_wallet_id }

        expect(wallet_entries.sum { it[:amount_cents] }).to eq(1500)
        expect(result[:charges_usage].sum { it[:amount_cents] }).to eq(3000)
      end
    end

    context "when charges sharing the billable metric each leave a unit to round" do
      let(:other_charge) { create(:standard_charge, plan:, billable_metric:) }
      let(:wallet_amounts) { {billable_metric.id => {first_wallet_id => 1, second_wallet_id => 1}} }
      let(:usage) do
        SubscriptionUsage.new(
          from_datetime: "2026-09-01T00:00:00Z",
          to_datetime: "2026-09-30T23:59:59Z",
          issuing_date: "2026-09-30",
          currency: "EUR",
          amount_cents: 2,
          total_amount_cents: 2,
          taxes_amount_cents: 0,
          fees: [
            build(:charge_fee, charge:, subscription:, units: "1", events_count: 1, amount_cents: 1, amount_currency: "EUR", charge_filter: nil, grouped_by: {}),
            build(:charge_fee, charge: other_charge, subscription:, units: "1", events_count: 1, amount_cents: 1, amount_currency: "EUR", charge_filter: nil, grouped_by: {})
          ]
        )
      end

      it "spreads the leftovers across wallets instead of giving them all to the first" do
        totals = result[:charges_usage].group_by { it[:wallet_id] }.transform_values do |entries|
          [entries.sum { it[:amount_cents] }, entries.sum { it[:events_count] }, entries.sum { BigDecimal(it[:units]) }]
        end

        expect(totals).to eq({first_wallet_id => [1, 1, 1], second_wallet_id => [1, 1, 1]})
      end
    end

    context "when the units carry decimals" do
      let(:wallet_amounts) { {billable_metric.id => {second_wallet_id => 600, first_wallet_id => 1050}} }
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
            build(:charge_fee, charge:, subscription:, units: "10.25", events_count: 4, amount_cents: 1000, amount_currency: "EUR", charge_filter: nil, grouped_by: {}),
            build(:charge_fee, charge:, subscription:, units: "5.5", events_count: 2, amount_cents: 500, amount_currency: "EUR", charge_filter: nil, grouped_by: {})
          ]
        )
      end

      it "keeps their precision and adds up exactly" do
        expect(entries.map { it[:units] }).to eq(["10.02", "5.73"])
      end
    end
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

    it "keeps a charge whose events cancelled out, since the events still happened" do
      usage.fees << build(:charge_fee, charge: unused_charge, subscription:, units: "0.0", events_count: 5,
        amount_cents: 0, amount_currency: "EUR", charge_filter: nil, grouped_by: {})

      entry = result[:charges_usage].find { it[:charge][:code] == unused_charge.code }

      expect(entry).to include(units: "0.0", amount_cents: 0, events_count: 5)
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

    context "when a wallet has absorbed nothing" do
      let(:wallet) { create(:wallet, customer:, organization:, currency: "EUR") }

      it "reports it at zero rather than dropping it from the list" do
        expect(result[:wallets]).to eq(
          [{lago_id: wallet.id, credits: "0.0", amount_cents: 0, amount_currency: "EUR"}]
        )
      end
    end
  end
end
