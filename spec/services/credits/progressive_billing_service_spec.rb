# frozen_string_literal: true

require 'rails_helper'

Rspec.describe Credits::ProgressiveBillingService, type: :service do
  subject(:credit_service) { described_class.new(invoice:) }

  let(:subscription) { create(:subscription, customer_id: customer.id) }
  let(:organization) { subscription.organization }
  let(:customer) { create(:customer) }
  let(:subscriptions) { [subscription] }

  let(:invoice) do
    create(:invoice,
      :subscription,
      customer:,
      organization:,
      sub_total_excluding_taxes_amount_cents: 1000,
      subscriptions: subscriptions)
  end

  let(:subscription_fees) { [subscription_fee1, subscription_fee2] }
  let(:subscription_fee1) { create(:charge_fee, invoice:, subscription:, amount_cents: 500) }
  let(:subscription_fee2) { create(:charge_fee, invoice:, subscription:, amount_cents: 500) }

  before do
    invoice
    invoice.invoice_subscriptions.each { |is| is.update!(charges_from_datetime: invoice.issuing_date - 1.month, charges_to_datetime: invoice.issuing_date) }
    subscription_fees
  end

  context "without progressive billing invoices" do
    describe "#call" do
      it "does not apply any credit to the invoice" do
        result = credit_service.call
        expect(result.credits).to be_empty
        expect(invoice.progressive_billing_credit_amount_cents).to be_zero
      end
    end
  end

  context "with one progressive billing invoice for the sole subscription" do
    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 1.day,
        fees_amount_cents: 20
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }

    before do
      progressive_billing_invoice
      progressive_billing_fee
    end

    describe "#call" do
      it "applies one credit to the invoice" do
        result = credit_service.call
        expect(result.credits.size).to eq(1)
        credit = result.credits.sole
        expect(credit.amount_cents).to eq(20)
        expect(invoice.progressive_billing_credit_amount_cents).to eq(20)

        expect(subscription_fee1.reload.precise_coupons_amount_cents).to eq(10)
        expect(subscription_fee2.reload.precise_coupons_amount_cents).to eq(10)
      end
    end
  end

  context "with multiple progressive billing invoices for the sole subscription" do
    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 2.days,
        fees_amount_cents: 20
      )
    end

    let(:progressive_billing_invoice2) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 1.day,
        fees_amount_cents: 200
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }
    let(:progressive_billing_fee2) { create(:charge_fee, amount_cents: 200, invoice: progressive_billing_invoice2) }

    before do
      progressive_billing_fee
      progressive_billing_fee2
    end

    describe "#call" do
      it "applies one credit to the invoice" do
        result = credit_service.call
        expect(result.credits.size).to eq(2)
        first_credit = result.credits.find { |credit| credit.progressive_billing_invoice == progressive_billing_invoice }
        expect(first_credit.amount_cents).to eq(20)

        first_credit = result.credits.find { |credit| credit.progressive_billing_invoice == progressive_billing_invoice2 }
        expect(first_credit.amount_cents).to eq(200)

        expect(invoice.progressive_billing_credit_amount_cents).to eq(220)
      end
    end
  end

  context "with multiple progressive billing invoices for the sole subscription with an amount higher than the subscription charges" do
    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 3.days,
        fees_amount_cents: 20
      )
    end

    let(:progressive_billing_invoice2) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 2.days,
        fees_amount_cents: 1000
      )
    end

    let(:progressive_billing_invoice3) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 1.day,
        fees_amount_cents: 200
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }
    let(:progressive_billing_fee2) { create(:charge_fee, amount_cents: 1000, invoice: progressive_billing_invoice2) }
    let(:progressive_billing_fee3) { create(:charge_fee, amount_cents: 200, invoice: progressive_billing_invoice3) }

    before do
      progressive_billing_fee
      progressive_billing_fee2
      progressive_billing_fee3
    end

    describe "#call" do
      it "applies one credit to the invoice" do
        result = credit_service.call
        expect(result.credits.size).to eq(2)
        first_credit = result.credits.find { |credit| credit.progressive_billing_invoice == progressive_billing_invoice }
        expect(first_credit.amount_cents).to eq(20)

        first_credit = result.credits.find { |credit| credit.progressive_billing_invoice == progressive_billing_invoice2 }
        expect(first_credit.amount_cents).to eq(980)

        expect(invoice.progressive_billing_credit_amount_cents).to eq(1000)
        expect(invoice.negative_amount_cents).to eq(-220)
      end
    end
  end

  context "with one progressive billing invoice for one subscription and one without" do
    let(:subscription2) { create(:subscription, customer_id: customer.id) }
    let(:subscriptions) { [subscription, subscription2] }

    let(:subscription_fees) { [subscription_fee1, subscription_fee2, subscription2_fee1, subscription2_fee2] }
    let(:subscription2_fee1) { create(:charge_fee, invoice:, subscription: subscription2, amount_cents: 500) }
    let(:subscription2_fee2) { create(:charge_fee, invoice:, subscription: subscription2, amount_cents: 500) }

    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 1.day,
        fees_amount_cents: 20
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }

    before do
      progressive_billing_invoice
      progressive_billing_fee
    end

    describe "#call" do
      it "applies one credit to the invoice" do
        result = credit_service.call
        expect(result.credits.size).to eq(1)
        credit = result.credits.sole
        expect(credit.amount_cents).to eq(20)
        expect(credit.progressive_billing_invoice).to eq(progressive_billing_invoice)
        expect(invoice.progressive_billing_credit_amount_cents).to eq(20)
      end
    end
  end

  context "with one progressive billing invoice outside the current billing boundaries for the sole subscription" do
    let(:progressive_billing_invoice) do
      create(
        :invoice,
        organization:,
        customer:,
        status: 'finalized',
        invoice_type: :progressive_billing,
        subscriptions: [subscription],
        issuing_date: invoice.issuing_date - 2.months,
        fees_amount_cents: 20
      )
    end

    let(:progressive_billing_fee) { create(:charge_fee, amount_cents: 20, invoice: progressive_billing_invoice) }

    before do
      progressive_billing_invoice
      progressive_billing_fee
    end

    describe "#call" do
      it "applies one credit to the invoice" do
        result = credit_service.call
        expect(result.credits).to be_empty
        expect(invoice.progressive_billing_credit_amount_cents).to eq(0)
      end
    end
  end
end
