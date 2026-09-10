# frozen_string_literal: true

require "rails_helper"

RSpec.describe Credits::ProgressiveBillingService, :premium do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:charges) do
    Array.new(2) { create(:standard_charge, plan:, billable_metric: create(:billable_metric, organization:)) }
  end
  let(:coupon_charges) { charges }
  let(:coupon_scope) { :billable_metrics }
  let(:period_start) { Time.zone.parse("2026-08-01") }
  let(:period_end) { Time.zone.parse("2026-08-31").end_of_day }
  let(:progressive_amounts) { [8708, 1631] }
  let(:final_amounts) { [9096, 1660] }

  let(:percentage_coupon) do
    create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 50,
      frequency: "recurring", frequency_duration: 12,
      limited_billable_metrics: coupon_scope == :billable_metrics, limited_plans: coupon_scope == :plans)
  end

  before do
    case coupon_scope
    when :billable_metrics
      coupon_charges.each do |charge|
        create(:coupon_billable_metric, organization:, coupon: percentage_coupon, billable_metric: charge.billable_metric)
      end
    when :plans
      create(:coupon_plan, organization:, coupon: percentage_coupon, plan:)
    end
    create(:applied_coupon, customer:, coupon: percentage_coupon, percentage_rate: 50,
      frequency: "recurring", frequency_duration: 12, frequency_duration_remaining: 12)
  end

  def build_invoice(invoice_type, amounts)
    invoice = create(:invoice, organization:, customer:, invoice_type:, status: :generating,
      issuing_date: (invoice_type == :progressive_billing) ? Date.new(2026, 8, 28) : Date.new(2026, 9, 1),
      fees_amount_cents: amounts.sum, sub_total_excluding_taxes_amount_cents: amounts.sum)
    create(:invoice_subscription, invoice:, subscription:, charges_from_datetime: period_start,
      charges_to_datetime: period_end, timestamp: invoice.issuing_date)
    charges.zip(amounts).each do |charge, amount|
      create(:charge_fee, invoice:, subscription:, charge:, amount_cents: amount, precise_amount_cents: amount,
        taxes_amount_cents: 0, taxes_precise_amount_cents: 0,
        properties: {charges_from_datetime: period_start, charges_to_datetime: period_end})
    end
    invoice
  end

  def apply_credits_and_finalize(invoice)
    Credits::ProgressiveBillingService.call!(invoice:, apply_coupons: true)
    Credits::AppliedCouponsService.call!(invoice:)
    invoice.fees.reload
    Invoices::ComputeAmountsFromFees.call!(invoice:)
    invoice.update!(status: :finalized)
    invoice
  end

  shared_examples "preserving progressively billed coupons" do
    it "preserves the percentage discount granted on the progressive invoice" do
      progressive_invoice = apply_credits_and_finalize(build_invoice(:progressive_billing, progressive_amounts))
      invoice = apply_credits_and_finalize(build_invoice(:subscription, final_amounts))

      expect(progressive_invoice.total_amount_cents).to eq(5169)
      expect(invoice.total_amount_cents).to eq(209)
      expect(progressive_invoice.total_amount_cents + invoice.total_amount_cents).to eq(5378)
    end

    context "with an additional fixed coupon, as reported in BIL-654" do
      before do
        coupon = create(:coupon, organization:, amount_cents: 4000, frequency: "forever")
        create(:applied_coupon, customer:, coupon:, amount_cents: 4000, frequency: "forever")
      end

      it "charges only the remaining 209 cents at period end" do
        progressive_invoice = apply_credits_and_finalize(build_invoice(:progressive_billing, progressive_amounts))
        invoice = apply_credits_and_finalize(build_invoice(:subscription, final_amounts))

        expect(progressive_invoice.coupons_amount_cents).to eq(9170)
        expect(progressive_invoice.total_amount_cents).to eq(1169)
        expect(invoice.total_amount_cents).to eq(209)
        expect(progressive_invoice.total_amount_cents + invoice.total_amount_cents).to eq(1378)
        expect(invoice.fees.sum(&:sub_total_excluding_taxes_amount_cents)).to eq(209)

        estimate = CreditNotes::EstimateService.call!(invoice:,
          items: invoice.fees.map { |fee| {fee_id: fee.id, amount_cents: fee.amount_cents} })
        expect(estimate.credit_note.credit_amount_cents).to eq(209)
      end
    end
  end

  include_examples "preserving progressively billed coupons"

  context "with an unrestricted percentage coupon" do
    let(:coupon_scope) { :unrestricted }

    include_examples "preserving progressively billed coupons"
  end

  context "with a percentage coupon limited to plans" do
    let(:coupon_scope) { :plans }

    include_examples "preserving progressively billed coupons"
  end

  context "when only one metric is discounted and the metrics have different taxes" do
    let(:coupon_charges) { charges.take(1) }
    let(:progressive_amounts) { [10_000, 10_000] }
    let(:final_amounts) { [11_000, 11_000] }

    before do
      charges.zip([10, 20]).each do |charge, rate|
        create(:charge_applied_tax, charge:, tax: create(:tax, organization:, rate:))
      end
    end

    it "allocates the net credit to the metrics that were billed" do
      apply_credits_and_finalize(build_invoice(:progressive_billing, progressive_amounts))
      invoice = apply_credits_and_finalize(build_invoice(:subscription, final_amounts))

      expect(invoice.fees.order(:amount_cents).map(&:sub_total_excluding_taxes_amount_cents)).to match_array([500, 1000])
      expect(invoice.taxes_amount_cents).to eq(250)
      expect(invoice.total_amount_cents).to eq(1750)
    end
  end

  context "with a fixed coupon first applied after progressive billing" do
    let(:progressive_amounts) { [10_000, 10_000] }

    it "discounts the remaining balance without refunding the progressive payment" do
      progressive_invoice = apply_credits_and_finalize(build_invoice(:progressive_billing, progressive_amounts))
      coupon = create(:coupon, organization:, amount_cents: 1000, frequency: "forever")
      create(:applied_coupon, customer:, coupon:, amount_cents: 1000, frequency: "forever")
      invoice = build_invoice(:subscription, progressive_amounts)
      create(:fee, invoice:, subscription:, amount_cents: 10_000, precise_amount_cents: 10_000,
        taxes_amount_cents: 0, taxes_precise_amount_cents: 0)
      invoice.update!(fees_amount_cents: 30_000, sub_total_excluding_taxes_amount_cents: 30_000)

      apply_credits_and_finalize(invoice)

      expect(progressive_invoice.credit_notes).to be_empty
      expect(invoice.progressive_billing_credit_amount_cents).to eq(10_000)
      expect(invoice.coupons_amount_cents).to eq(11_000)
      expect(invoice.total_amount_cents).to eq(9000)
      expect(invoice.fees.sum(&:sub_total_excluding_taxes_amount_cents)).to eq(9000)
    end
  end
end
