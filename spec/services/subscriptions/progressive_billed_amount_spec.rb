# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscriptions::ProgressiveBilledAmount, type: :service do
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
      expect(result.progressive_billing_invoice).to be_nil
    end
  end

  context "with progressive billing invoice for another subscription" do
    let(:other_subscription) { create(:subscription, customer_id: customer.id) }
    let(:invoice_subscription) { create(:invoice_subscription, subscription: other_subscription, charges_from_datetime:, charges_to_datetime:) }
    let(:other_invoice) { invoice_subscription.invoice }

    before do
      other_invoice.update!(invoice_type:, fees_amount_cents: 20)
    end

    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
    end
  end

  context "with progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }

    before do
      invoice.update!(invoice_type:, fees_amount_cents: 20)
    end

    it "returns the fees_amount_cents from that invoice" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(20)
      expect(result.progressive_billing_invoice).to eq(invoice)
    end
  end

  context "with progressive billing invoice for this subscription in previous period" do
    let(:charges_to_datetime) { timestamp - 1.week }
    let(:charges_from_datetime) { timestamp - 2.weeks }
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }

    before do
      invoice.update!(invoice_type:, fees_amount_cents: 20)
    end

    it "returns 0" do
      result = service.call
      expect(result.progressive_billed_amount).to be_zero
      expect(result.progressive_billing_invoice).to be_nil
    end
  end

  context "with multiple progressive billing invoice for this subscription" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:invoice_subscription2) { create(:invoice_subscription, subscription:, charges_from_datetime:, charges_to_datetime:) }
    let(:invoice2) { invoice_subscription2.invoice }

    before do
      invoice.update!(invoice_type:, issuing_date: timestamp - 2.days, fees_amount_cents: 20)
      invoice2.update!(invoice_type:, issuing_date: timestamp - 1.day, fees_amount_cents: 40)
    end

    it "returns the last issued invoice fees_amount_cents" do
      result = service.call
      expect(result.progressive_billed_amount).to eq(40)
      expect(result.progressive_billing_invoice).to eq(invoice2)
    end
  end
end
