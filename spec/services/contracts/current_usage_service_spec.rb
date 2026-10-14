# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::CurrentUsageService do
  subject(:result) { described_class.call!(contract:, timestamp:, apply_taxes:, filters:) }

  let(:filters) { {} }
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
    usage = result.rate_card_usages.sole

    expect(usage.contract_rate_card).to eq(contract_rate_card)
    expect(usage.billing_segment).to be_new_record
    expect(usage.billing_segment).to have_attributes(
      rate_card_rate: rate, started_at: Time.zone.parse("2027-02-01"),
      ended_at: BillingSegment.inclusive_end(Time.zone.parse("2027-03-01"))
    )
    expect(usage.fees.sole).to be_new_record
    expect(usage.fees.sole).to have_attributes(fee_type: "product", contract_rate_card:, units: 1, amount_cents: 200)
    expect(usage.invoice_id).to be_nil
    expect(result).to have_attributes(amount_cents: 200, taxes_amount_cents: 0, total_amount_cents: 200)
  end

  it "persists nothing" do
    expect { result }.not_to change { [Fee.count, BillingSegment.count] }
  end

  context "with an earlier timestamp" do
    let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

    it "prices the window open at that timestamp" do
      usage = result.rate_card_usages.sole

      expect(usage.billing_segment.started_at).to eq(Time.zone.parse("2027-01-01"))
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 200)
    end
  end

  context "when the card is not effective yet" do
    let(:effective_date) { Date.new(2027, 2, 15) }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
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
      usage = result.rate_card_usages.sole

      expect(usage.contract_rate_card).to eq(new_contract_rate_card)
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 500)
    end

    context "when filtering on the superseded version" do
      let(:filters) { {rate_card_code: rate_card.code} }

      it "returns no window" do
        expect(result.rate_card_usages).to eq([])
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
      usage = result.rate_card_usages.sole

      expect(usage.rate_phase).to eq(intro_phase)
      expect(usage.billing_segment.rate_override).to eq(intro_phase.rate_override)
      expect(usage.fees.sole).to have_attributes(units: 1, amount_cents: 100)
    end

    context "when the phase is over" do
      let(:timestamp) { Time.zone.parse("2027-03-10 12:00:00") }

      it "prices the window with the card's rate" do
        usage = result.rate_card_usages.sole

        expect(usage.rate_phase).to be_nil
        expect(usage.billing_segment.rate_override).to be_nil
      end
    end
  end

  context "with a customer timezone behind UTC" do
    let(:customer) { create(:customer, organization:, timezone: "America/Argentina/Buenos_Aires", currency: "EUR") }
    # Jan 31, 23:00 in the customer timezone.
    let(:timestamp) { Time.utc(2027, 2, 1, 2) }
    let(:new_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: new_rate_card,
        effective_date: Date.new(2027, 2, 1), billing_anchor_date: Date.new(2027, 2, 1))
      create(:rate_card_rate, organization:, rate_card: new_rate_card, effective_from: Time.utc(2027, 2, 1, 3))
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.utc(2027, 2, 1, 1))
    end

    it "prices the customer's local window with the version effective on the customer's date" do
      usage = result.rate_card_usages.sole

      expect(usage.contract_rate_card).to eq(contract_rate_card)
      expect(usage.billing_segment).to have_attributes(
        started_at: Time.utc(2027, 1, 1, 3), ended_at: BillingSegment.inclusive_end(Time.utc(2027, 2, 1, 3))
      )
      expect(usage.units).to eq(2)
    end

    context "when the customer's day has turned" do
      let(:timestamp) { Time.utc(2027, 2, 1, 3, 30) }

      it "prices the next local window with the new version" do
        usage = result.rate_card_usages.sole

        expect(usage.contract_rate_card.rate_card).to eq(new_rate_card)
        expect(usage.billing_segment.started_at).to eq(Time.utc(2027, 2, 1, 3))
      end
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
      expect(result).to have_attributes(amount_cents: 0, taxes_amount_cents: 0, total_amount_cents: 0)
    end
  end

  context "with a product type filter" do
    let(:filters) { {product_type: "fixed"} }
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
      expect(result.rate_card_usages.map { |usage| usage.contract_rate_card.rate_card }).to eq([fixed_rate_card])
      expect(result.amount_cents).to eq(1000)
    end
  end

  context "with a card scoped to a product filter and a card on another product" do
    let(:eu_filter) { create(:product_filter, organization:, product:) }
    let(:eu_rate_card) { create(:rate_card, organization:, product:, product_filter: eu_filter, currency: "EUR") }
    let(:other_product) { create(:product, :metered, organization:, billable_metric:) }
    let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "EUR") }
    let(:priced_cards) do
      result.rate_card_usages.to_h { |usage| [usage.contract_rate_card.rate_card, usage.units] }
    end

    before do
      region = create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us])
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
      [eu_rate_card, other_rate_card].each do |scoped_rate_card|
        create(:contract_rate_card, organization:, contract:, rate_card: scoped_rate_card,
          effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
        create(:rate_card_rate, organization:, rate_card: scoped_rate_card, effective_from: Time.zone.parse("2027-01-01"))
      end
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: billable_metric.code, timestamp: Time.zone.parse("2027-02-06"), properties: {region: "eu"})
    end

    it "prices each card on the events it targets" do
      expect(priced_cards).to eq(rate_card => 1, eu_rate_card => 1, other_rate_card => 2)
    end

    context "with a product code filter" do
      let(:filters) { {product_code: product.code} }

      it "prices the cards of that product only" do
        expect(priced_cards.keys).to contain_exactly(rate_card, eu_rate_card)
      end
    end

    context "with a product filter code filter" do
      let(:filters) { {product_filter_code: eu_filter.code} }

      it "prices the card scoped to that filter only" do
        expect(priced_cards.keys).to eq([eu_rate_card])
      end
    end

    context "with filters no card matches together" do
      let(:filters) { {product_code: other_product.code, product_filter_code: eu_filter.code} }

      it "returns no usage" do
        expect(result.rate_card_usages).to eq([])
      end
    end
  end

  context "with an unknown product type" do
    subject(:result) { described_class.call(contract:, timestamp:, apply_taxes:, filters:) }

    let(:filters) { {product_type: "usage"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(product_type: ["value_is_invalid"])
    end
  end

  context "with several cards" do
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", code: "a_monthly") }
    let(:codes) { result.rate_card_usages.map { |usage| usage.contract_rate_card.rate_card.code } }

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
      expect(result.rate_card_usages.sole.invoice_id).to be_nil
    end
  end

  context "without a rate" do
    let(:rate) { nil }

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
    end
  end

  context "when the contract ended before the timestamp" do
    let(:contract) do
      create(:contract, :terminated, organization:, customer:, started_at: Time.zone.parse("2027-01-01"),
        ended_at: Time.zone.parse("2027-02-01"))
    end

    it "returns no window" do
      expect(result.rate_card_usages).to eq([])
    end
  end

  context "with taxes" do
    let(:apply_taxes) { true }

    before do
      create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 20))
    end

    it "applies the customer taxes" do
      expect(result.rate_card_usages.sole.fees.sole).to have_attributes(taxes_amount_cents: 40)
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
      usage = result.rate_card_usages.sole

      expect(usage.fees.sole).to have_attributes(fee_type: "product", units: 3, amount_cents: 3000)
      expect(usage.invoice_id).to be_nil
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
        expect(result.rate_card_usages.sole.invoice_id).to eq(february_invoice.id)
      end

      context "with an earlier timestamp" do
        let(:timestamp) { Time.zone.parse("2027-01-20 12:00:00") }

        it "returns the invoice that billed the window open at that timestamp" do
          expect(result.rate_card_usages.sole.invoice_id).to eq(january_invoice.id)
        end
      end

      context "with another fixed card billed in advance" do
        let(:other_rate_card) do
          create(:rate_card, organization:, product: create(:product, :fixed, organization:), billing_timing: :advance,
            currency: "EUR")
        end
        let(:other_invoice) { create(:invoice, organization:, customer:) }

        before do
          other_contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card,
            units: 1, effective_date: Date.new(2027, 1, 1), billing_anchor_date: Date.new(2027, 1, 1))
          other_rate = create(:rate_card_rate, organization:, rate_card: other_rate_card,
            effective_from: Time.zone.parse("2027-01-01"))
          create(:billing_segment, organization:, customer:, contract:, contract_rate_card: other_contract_rate_card,
            rate_card_rate: other_rate, status: :done, invoice: other_invoice,
            cycle_started_at: Time.zone.parse("2027-02-01"), billing_at: Time.zone.parse("2027-02-01"))
        end

        it "finds both invoices in a single query" do
          usages = nil
          statements = capture_sql { usages = result.rate_card_usages }

          expect(usages.to_h { |usage| [usage.contract_rate_card.rate_card, usage.invoice_id] })
            .to eq(rate_card => february_invoice.id, other_rate_card => other_invoice.id)
          expect(statements.grep(/FROM "billing_segments"/).size).to eq(1)
        end
      end
    end
  end
end
