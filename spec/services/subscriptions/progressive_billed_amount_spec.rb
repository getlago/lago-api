# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::ProgressiveBilledAmount do
  subject(:service) { described_class.new(subscription:, timestamp:) }

  let(:timestamp) { Time.current }
  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }

  let(:charges_to_datetime) { timestamp + 1.week }
  let(:charges_from_datetime) { timestamp - 1.week }
  let(:invoice_type) { :progressive_billing }

  context "without previous progressive billing invoices" do
    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.total_billed_amount_cents).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
      expect(result.to_credit_amount).to be_zero
    end
  end

  context "with progressive billing invoice for another subscription" do
    let(:other_subscription) { create(:subscription, customer_id: customer.id) }
    let(:invoice_subscription) { create(:invoice_subscription, subscription: other_subscription, charges_from_datetime:, charges_to_datetime:) }
    let(:other_invoice) { invoice_subscription.invoice }

    before do
      other_invoice.update!(invoice_type:, fees_amount_cents: 20, total_amount_cents: 20)
    end

    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.total_billed_amount_cents).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
      expect(result.to_credit_amount).to be_zero
    end
  end

  context "with progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:fee) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, taxes_amount_cents: 0) }

    before do
      fee
      invoice.update!(invoice_type:, fees_amount_cents: 20, total_amount_cents: 20)
    end

    it "returns the fees_amount_cents from that invoice" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(20)
      expect(result.total_billed_amount_cents).to eq(20)
      expect(result.progressive_billing_invoice).to eq(invoice)
      expect(result.to_credit_amount).to eq(20)
    end
  end

  context "with failed progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:fee) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, taxes_amount_cents: 0) }

    before do
      fee
      invoice.update!(invoice_type:, status: :failed, fees_amount_cents: 20, prepaid_credit_amount_cents: 20)
    end

    it "returns the fees_amount_cents from that invoice" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(20)
      expect(result.total_billed_amount_cents).to eq(20)
      expect(result.progressive_billing_invoice).to eq(invoice)
      expect(result.to_credit_amount).to eq(20)
    end
  end

  context "with generating progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:fee) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, taxes_amount_cents: 0) }

    before do
      fee
      invoice.update!(invoice_type:, status: :generating, fees_amount_cents: 20, prepaid_credit_amount_cents: 20)
    end

    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.total_billed_amount_cents).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
      expect(result.to_credit_amount).to be_zero
    end

    context "when passing include_generating_invoices: true" do
      subject(:service) { described_class.new(subscription:, timestamp:, include_generating_invoices: true) }

      it "returns the fees_amount_cents from that invoice" do
        result = service.call
        expect(result.progressive_billed_amount).to eq(20)
        expect(result.total_billed_amount_cents).to eq(20)
        expect(result.progressive_billing_invoice).to eq(invoice)
        expect(result.to_credit_amount).to eq(20)
      end
    end
  end

  context "with progressive billing invoice for this subscription in previous period" do
    let(:charges_to_datetime) { timestamp - 1.week }
    let(:charges_from_datetime) { timestamp - 2.weeks }
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }

    before do
      invoice.update!(invoice_type:, fees_amount_cents: 20, prepaid_credit_amount_cents: 20)
    end

    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.total_billed_amount_cents).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
      expect(result.to_credit_amount).to be_zero
    end
  end

  context "with multiple progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:fee1) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, taxes_amount_cents: 0) }
    let(:invoice_subscription2) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice2) { invoice_subscription2.invoice }
    let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, taxes_amount_cents: 0, precise_coupons_amount_cents: 20) }

    before do
      fee1
      fee2
      invoice.update!(invoice_type:, issuing_date: timestamp - 2.days, fees_amount_cents: 20, total_amount_cents: 0, prepaid_credit_amount_cents: 20)
      invoice2.update!(invoice_type:, issuing_date: timestamp - 1.day, fees_amount_cents: 40, total_amount_cents: 10, prepaid_credit_amount_cents: 10)
    end

    it "returns the last issued invoice fees_amount_cents" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(40)
      expect(result.total_billed_amount_cents).to eq(40)
      expect(result.progressive_billing_invoice).to eq(invoice2)
      expect(result.to_credit_amount).to eq(40)
    end
  end

  context "with multiple progressive billing invoice for this subscription and the last one failed" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:fee1) { create(:charge_fee, invoice:, subscription:, amount_cents: 20, taxes_amount_cents: 0) }
    let(:invoice_subscription2) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice2) { invoice_subscription2.invoice }
    let(:fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 40, taxes_amount_cents: 0, precise_coupons_amount_cents: 20) }

    before do
      fee1
      fee2
      invoice.update!(invoice_type:, issuing_date: timestamp - 2.days, fees_amount_cents: 20)
      invoice2.update!(invoice_type:, status: :failed, issuing_date: timestamp - 1.day, fees_amount_cents: 40)
    end

    it "returns the last issued invoice fees_amount_cents" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(40)
      expect(result.total_billed_amount_cents).to eq(40)
      expect(result.progressive_billing_invoice).to eq(invoice2)
      expect(result.to_credit_amount).to eq(40)
    end
  end

  context "with progressive billing invoice for this subscription, but it has a credit note" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:credit_note) { create(:credit_note, invoice:, credit_amount_cents:) }

    before do
      invoice.update!(invoice_type:, fees_amount_cents: 20)
      credit_note
    end

    context "when fully credited" do
      let(:credit_amount_cents) { 20 }

      it "returns the fees_amount_cents from that invoice" do
        result = service.call
        expect(result.progressive_billed_amount).to eq(20)
        expect(result.progressive_billing_invoice).to eq(invoice)
        expect(result.to_credit_amount).to eq(0)
      end
    end

    context "when partially credited" do
      let(:credit_amount_cents) { 10 }

      it "returns the fees_amount_cents from that invoice" do
        result = service.call
        expect(result.progressive_billed_amount).to eq(20)
        expect(result.progressive_billing_invoice).to eq(invoice)
        expect(result.to_credit_amount).to eq(10)
      end
    end
  end

  context "with progressive billing invoice for this subscription, but it has already been applied to an invoice" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:progressive_billing_invoice) { invoice_subscription.invoice }
    let(:other_invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { other_invoice_subscription.invoice }
    let(:progressive_billing_credit) do
      create(:credit,
        invoice:,
        progressive_billing_invoice:,
        amount_cents: amount_to_credit,
        amount_currency: invoice.currency,
        before_taxes: true)
    end

    before do
      progressive_billing_credit
      progressive_billing_invoice.update!(invoice_type:, fees_amount_cents: 20)
    end

    context "when fully credited" do
      let(:amount_to_credit) { 20 }

      it "returns the fees_amount_cents from that invoice" do
        result = service.call
        expect(result.progressive_billed_amount).to eq(20)
        expect(result.progressive_billing_invoice).to eq(progressive_billing_invoice)
        expect(result.to_credit_amount).to eq(0)
      end
    end

    context "when partially credited" do
      let(:amount_to_credit) { 10 }

      it "returns the fees_amount_cents from that invoice" do
        result = service.call
        expect(result.progressive_billed_amount).to eq(20)
        expect(result.progressive_billing_invoice).to eq(progressive_billing_invoice)
        expect(result.to_credit_amount).to eq(10)
      end
    end
  end
end
