# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::CalculateApplicableFeesService do
  subject(:service_result) { described_class.call(wallet:, invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents:) }
  let(:total_amount_cents) { 0 }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

  describe "#total_amount_cents" do
    context "without wallet limitations" do
      let(:total_amount_cents) { 110 }
      let(:fee) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10) }

      before { fee }

      it "returns the sum of all fees" do
        expect(service_result.total_amount_cents).to eq(110)
      end
    end

    context "with billable metric limitations" do
      let(:total_amount_cents) { 330 }
      let(:wallet) { create(:wallet, customer:) }
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }

      let(:other_billable_metric) { create(:billable_metric, organization:) }
      let(:other_charge) { create(:standard_charge, plan: subscription.plan, billable_metric: other_billable_metric) }

      let(:limited_fee) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10) }
      let(:non_limited_fee) { create_fee(invoice, other_charge, subscription, amount: 200, taxes: 20) }

      before do
        wallet_target
        limited_fee
        non_limited_fee
      end

      it "only includes fees matching billable metric limitations" do
        expect(service_result.total_amount_cents).to eq(110)
      end
    end

    context "with fee type limitations" do
      let(:total_amount_cents) { 330 }
      let(:wallet) { create(:wallet, customer:, allowed_fee_types: ["subscription"]) }

      let(:subscription_fee) do
        create(
          :fee,
          invoice:,
          subscription:,
          fee_type: "subscription",
          amount_cents: 100,
          precise_amount_cents: 100,
          taxes_amount_cents: 10,
          taxes_precise_amount_cents: 10,
          precise_coupons_amount_cents: 0
        )
      end
      let(:charge_fee) { create_fee(invoice, charge, subscription, amount: 200, taxes: 20) }

      before do
        subscription_fee
        charge_fee
      end

      it "only includes fees matching fee type limitations" do
        expect(service_result.total_amount_cents).to eq(110)
      end
    end

    context "with coupons applied" do
      let(:total_amount_cents) { 110 }
      let(:wallet) { create(:wallet, customer:, allowed_fee_types: ["charge"]) }
      let(:fee_with_coupon) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10, coupons: 30) }

      before { fee_with_coupon }

      it "deducts coupons from fee amounts" do
        # 100 - 30 (coupon) + 10 (taxes) = 80
        expect(service_result.total_amount_cents).to eq(80)
      end
    end

    context "with credit notes applied" do
      let(:total_amount_cents) { 110 }
      let(:wallet) { create(:wallet, customer:, allowed_fee_types: ["charge"]) }
      let(:fee_with_credit_note) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10, credit_notes: 25) }

      before { fee_with_credit_note }

      it "deducts credit notes from fee amounts" do
        # 100 + 10 (taxes) - 25 (credit note) = 85
        expect(service_result.total_amount_cents).to eq(85)
      end
    end

    context "with both billable metric and fee type limitations" do
      let(:total_amount_cents) { 385 }
      let(:wallet) { create(:wallet, customer:, allowed_fee_types: ["subscription"]) }
      let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }

      let(:other_billable_metric) { create(:billable_metric, organization:) }
      let(:other_charge) { create(:standard_charge, plan: subscription.plan, billable_metric: other_billable_metric) }

      let(:limited_charge_fee) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10) }
      let(:non_limited_charge_fee) { create_fee(invoice, other_charge, subscription, amount: 200, taxes: 20) }
      let(:subscription_fee) do
        create(
          :fee,
          invoice:,
          subscription:,
          fee_type: "subscription",
          amount_cents: 50,
          precise_amount_cents: 50,
          taxes_amount_cents: 5,
          taxes_precise_amount_cents: 5,
          precise_coupons_amount_cents: 0
        )
      end

      before do
        wallet_target
        limited_charge_fee
        non_limited_charge_fee
        subscription_fee
      end

      it "includes billable metric limited charges and fee type limited fees" do
        # limited_charge_fee: 110 (matches billable metric)
        # subscription_fee: 55 (matches fee type)
        # non_limited_charge_fee: excluded (doesn't match billable metric, and subscription fee type doesn't include charge)
        expect(service_result.total_amount_cents).to eq(165)
      end
    end
  end

  describe "applicable_fees" do
    let(:total_amount_cents) { 110 }
    let(:fee) { create_fee(invoice, charge, subscription, amount: 100, taxes: 10) }

    before { fee }

    it "returns the list of applicable fees" do
      expect(service_result.applicable_fees).to contain_exactly(fee)
    end
  end

  describe "rounding safeguard" do
    let(:wallet) { create(:wallet, customer:, allowed_fee_types: ["charge"]) }
    let(:total_amount_cents) { 99 }

    # Simulates rounding where individual fees round down but sum would exceed invoice total
    # Fee 1: precise 33.4 → rounded to 33
    # Fee 2: precise 33.4 → rounded to 33
    # Fee 3: precise 33.4 → rounded to 33
    # Invoice total: 99, but precise sum: 100.2
    let(:fee1) { create_fee_with_precise(invoice, charge, subscription, amount: 33, precise_amount: 33.4, taxes: 0, precise_taxes: 0) }
    let(:fee2) { create_fee_with_precise(invoice, charge, subscription, amount: 33, precise_amount: 33.4, taxes: 0, precise_taxes: 0) }
    let(:fee3) { create_fee_with_precise(invoice, charge, subscription, amount: 33, precise_amount: 33.4, taxes: 0, precise_taxes: 0) }

    before do
      fee1
      fee2
      fee3
    end

    it "caps at invoice total when precise sum exceeds it" do
      # Precise sum would be 100.2, but capped at invoice total of 99
      expect(service_result.total_amount_cents).to eq(99)
    end
  end

  def create_fee(invoice, charge, subscription, amount:, taxes:, coupons: 0, credit_notes: 0)
    create(
      :charge_fee,
      invoice:,
      charge:,
      subscription:,
      amount_cents: amount,
      precise_amount_cents: amount,
      taxes_amount_cents: taxes,
      taxes_precise_amount_cents: taxes,
      precise_coupons_amount_cents: coupons,
      precise_credit_notes_amount_cents: credit_notes
    )
  end

  def create_fee_with_precise(invoice, charge, subscription, amount:, precise_amount:, taxes:, precise_taxes:)
    create(
      :charge_fee,
      invoice:,
      charge:,
      subscription:,
      amount_cents: amount,
      precise_amount_cents: precise_amount,
      taxes_amount_cents: taxes,
      taxes_precise_amount_cents: precise_taxes,
      precise_coupons_amount_cents: 0,
      precise_credit_notes_amount_cents: 0
    )
  end
end
