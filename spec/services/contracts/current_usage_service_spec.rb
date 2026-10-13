# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CurrentUsageService do
  subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes:) }

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
