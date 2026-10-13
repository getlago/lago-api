# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CurrentUsageService do
  subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes:, filters:) }

  let(:filters) { described_class::Filters.new }
  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:timestamp) { Time.zone.parse("2027-02-10 12:00:00") }
  let(:apply_taxes) { false }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:billing_timing) { :arrears }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "EUR") }
  let(:effective_date) { Date.new(2027, 1, 1) }
  let(:units) { nil }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units:,
      effective_date:, billing_anchor_date: Date.new(2027, 1, 1))
  end
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
      rate_properties: {"amount" => "2"})
  end

  before do
    contract_rate_card
    rate
    [Time.zone.parse("2027-01-10"), Time.zone.parse("2027-02-05")].each do |event_timestamp|
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: event_timestamp)
    end
  end

  it "prices the window open at the timestamp" do
    window = result.card_windows.sole

    expect(window.contract_rate_card).to eq(contract_rate_card)
    expect(window.billing_segment).to be_new_record
    expect(window.billing_segment).to have_attributes(
      rate_card_rate: rate, started_at: Time.zone.parse("2027-02-01"),
      ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01"))
    )
    expect(window.fees.sole).to be_new_record
    expect(window.fees.sole).to have_attributes(fee_type: "product", contract_rate_card:, units: 1, amount_cents: 200)
    expect(window.invoice_id).to be_nil
    expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, total_amount_cents: 200)
  end

  it "persists nothing" do
    expect { result }.not_to change { [Fee.count, BillingSegment.count] }
  end

  context "with an earlier timestamp" do
    let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

    it "prices the window open at that timestamp" do
      window = result.card_windows.sole

      expect(window.billing_segment.started_at).to eq(Time.zone.parse("2027-01-01"))
      expect(window.fees.sole).to have_attributes(units: 1, amount_cents: 200)
    end
  end

  context "when the card is not effective yet" do
    let(:effective_date) { Date.new(2027, 2, 15) }

    it "returns no window" do
      expect(result.card_windows).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "with a newer version of the card" do
    let(:new_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
    let(:new_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: new_rate_card,
        effective_date: Date.new(2027, 2, 1), billing_anchor_date: Date.new(2027, 2, 1))
    end

    before do
      new_contract_rate_card
      create(:rate_card_rate, organization:, rate_card: new_rate_card, effective_from: Time.zone.parse("2027-02-01"),
        rate_properties: {"amount" => "5"})
    end

    it "prices the version effective at the timestamp only" do
      window = result.card_windows.sole

      expect(window.contract_rate_card).to eq(new_contract_rate_card)
      expect(window.fees.sole).to have_attributes(units: 1, amount_cents: 500)
    end

    context "when filtering on the superseded version" do
      let(:filters) { described_class::Filters.new(rate_card_code: rate_card.code) }

      it "returns no window" do
        expect(result.card_windows).to eq([])
      end
    end
  end

  context "with an intro phase" do
    let(:intro_phase) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, plan_rate_card: nil, code: "intro",
        position: 1, billing_interval_cycle_count: 2,
        rate_override: create(:rate_override, organization:, rate_properties: {"amount" => "1"}))
    end

    before { intro_phase }

    it "prices the window with the phase override" do
      window = result.card_windows.sole

      expect(window.rate_phase).to eq(intro_phase)
      expect(window.billing_segment.rate_override).to eq(intro_phase.rate_override)
      expect(window.fees.sole).to have_attributes(units: 1, amount_cents: 100)
    end

    context "when the phase is over" do
      let(:timestamp) { Time.zone.parse("2027-03-10 12:00:00") }

      it "prices the window with the card's rate" do
        window = result.card_windows.sole

        expect(window.rate_phase).to be_nil
        expect(window.billing_segment.rate_override).to be_nil
      end
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }

    it "returns no window" do
      expect(result.card_windows).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "with a product type filter" do
    let(:filters) { described_class::Filters.new(product_type: "fixed") }
    let(:fixed_rate_card) do
      create(:rate_card, organization:, product: create(:product, :fixed, organization:), currency: "EUR")
    end

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: fixed_rate_card, units: 1,
        effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
      create(:rate_card_rate, organization:, rate_card: fixed_rate_card, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "10"})
    end

    it "prices the matching cards only" do
      expect(result.card_windows.map { |window| window.contract_rate_card.rate_card }).to eq([fixed_rate_card])
      expect(result.amount_cents).to eq(1000)
    end
  end

  context "with several cards" do
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", code: "a_monthly") }
    let(:codes) { result.card_windows.map { |window| window.contract_rate_card.rate_card.code } }

    before do
      [
        ["b_mid_month", Date.new(2027, 1, 1), Date.new(2027, 1, 15), "month"],
        ["c_weekly", Date.new(2027, 2, 1), Date.new(2027, 2, 1), "week"]
      ].each do |code, effective_date, billing_anchor_date, billing_interval_unit|
        other_rate_card = create(:rate_card, organization:, code:, currency: "EUR",
          product: create(:product, :metered, organization:, billable_metric:))
        create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, effective_date:, billing_anchor_date:)
        create(:rate_card_rate, organization:, rate_card: other_rate_card, billing_interval_unit:,
          effective_from: effective_date.in_time_zone)
      end
    end

    it "orders the windows by start" do
      expect(codes).to eq(%w[b_mid_month a_monthly c_weekly])
    end

    context "with windows opening at the same instant" do
      let(:timestamp) { Time.zone.parse("2027-02-03 12:00:00") }

      it "puts the window closing first ahead" do
        expect(codes).to eq(%w[b_mid_month c_weekly a_monthly])
      end
    end
  end

  context "with a metered card billed in advance" do
    let(:billing_timing) { :advance }

    before do
      create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate: rate,
        status: :done, invoice: create(:invoice, organization:, customer:),
        cycle_started_at: Time.zone.parse("2027-02-01"), billing_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no invoice, as each event is billed on its own" do
      expect(result.card_windows.sole.invoice_id).to be_nil
    end
  end

  context "without a rate" do
    let(:rate) { nil }

    it "returns no window" do
      expect(result.card_windows).to eq([])
    end
  end

  context "when the contract ended before the timestamp" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        ended_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no window" do
      expect(result.card_windows).to eq([])
    end
  end

  context "with taxes" do
    let(:apply_taxes) { true }

    before do
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
    end

    it "applies the customer taxes" do
      expect(result.card_windows.sole.fees.sole).to have_attributes(taxes_amount_cents: 40)
      expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 40, total_amount_cents: 240)
    end
  end

  context "with a fixed card" do
    let(:product) { create(:product, :fixed, organization:) }
    let(:units) { 3 }
    let(:rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "10"})
    end

    it "prices the card's units for the window" do
      window = result.card_windows.sole

      expect(window.fees.sole).to have_attributes(fee_type: "product", units: 3, amount_cents: 3000)
      expect(window.invoice_id).to be_nil
    end

    context "when billed in advance" do
      let(:billing_timing) { :advance }
      let(:january_invoice) { create(:invoice, organization:, customer:) }
      let(:february_invoice) { create(:invoice, organization:, customer:) }

      before do
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate: rate,
          status: :done, invoice: january_invoice,
          cycle_started_at: Time.zone.parse("2027-01-01"), billing_at: Time.zone.parse("2027-01-01"))
        create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate: rate,
          status: :done, invoice: february_invoice,
          cycle_started_at: Time.zone.parse("2027-02-01"), billing_at: Time.zone.parse("2027-02-01"))
      end

      it "returns the invoice that billed the open window" do
        expect(result.card_windows.sole.invoice_id).to eq(february_invoice.id)
      end

      context "with an earlier timestamp" do
        let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

        it "returns the invoice that billed the window open at that timestamp" do
          expect(result.card_windows.sole.invoice_id).to eq(january_invoice.id)
        end
      end
    end
  end
end
