# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::RefundPaymentService do
  subject(:service_result) { described_class.call(payment:, reason:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, status: :closed) }
  let(:reason) { :subscription_activation_expired }
  let(:payment_provider) { create(:stripe_provider, organization:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider:) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: stripe_customer,
      organization:,
      customer:,
      provider_payment_id: "pi_123",
      payable_payment_status: :succeeded,
      amount_cents: 25_00,
      amount_currency: "EUR"
    )
  end

  let(:stripe_refund_row) do
    build_stubbed(:refund, payment:, refundable: invoice, organization:, reason: :subscription_activation_expired)
  end
  let(:stripe_service_result) do
    PaymentProviders::Stripe::Payments::RefundService::Result.new.tap do |r|
      r.payment = payment
      r.refund = stripe_refund_row
    end
  end

  before do
    allow(PaymentProviders::Stripe::Payments::RefundService).to receive(:call!).and_return(stripe_service_result)
  end

  context "when the payment provider is Stripe" do
    it "delegates to the Stripe refund service with payment and reason" do
      service_result

      expect(PaymentProviders::Stripe::Payments::RefundService).to have_received(:call!).with(payment:, reason:)
    end

    it "returns the payment and the underlying refund" do
      expect(service_result).to be_success
      expect(service_result.payment).to eq(payment)
      expect(service_result.refund).to eq(stripe_refund_row)
    end
  end

  context "when the payment has no payment_provider" do
    let(:payment) do
      create(:payment, payable: invoice, payment_provider: nil, organization:, customer:,
        provider_payment_id: "pi_123", payable_payment_status: :succeeded)
    end

    it "returns a successful result without dispatching" do
      expect(service_result).to be_success
      expect(service_result.refund).to be_nil
      expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
    end
  end

  context "when the payment has no provider_payment_id" do
    before { payment.update!(provider_payment_id: nil) }

    it "returns a successful result without dispatching" do
      expect(service_result).to be_success
      expect(service_result.refund).to be_nil
      expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
    end
  end

  context "when a Refund row already exists for the payment" do
    let(:existing_refund) do
      create(:refund, :subscription_activation_expired, payment:, refundable: invoice, organization:)
    end

    before { existing_refund }

    it "returns the existing refund without dispatching" do
      expect(service_result).to be_success
      expect(service_result.refund).to eq(existing_refund)
      expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
    end

    context "when the existing refund has a different reason" do
      let(:existing_refund) do
        create(:refund, payment:, refundable: invoice, organization:, reason: :credit_note,
          credit_note: create(:credit_note, customer:, organization:))
      end

      it "still short-circuits — a payment can only be refunded once" do
        expect(service_result).to be_success
        expect(service_result.refund).to eq(existing_refund)
        expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
      end
    end

    context "when the existing refund is failed" do
      let(:existing_refund) do
        create(:refund, :subscription_activation_expired, payment:, refundable: invoice, organization:, status: "failed")
      end

      it "still short-circuits — failed refunds need manual ops, not retry" do
        expect(service_result).to be_success
        expect(service_result.refund).to eq(existing_refund)
        expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
      end
    end
  end

  context "when the payment provider has no refund integration" do
    let(:payment_provider) { create(:cashfree_provider, organization:) }
    let(:payment) do
      create(:payment, payable: invoice, payment_provider:, organization:, customer:,
        provider_payment_id: "cf_123", payable_payment_status: :succeeded)
    end

    it "returns a successful result without dispatching" do
      expect(service_result).to be_success
      expect(service_result.refund).to be_nil
      expect(PaymentProviders::Stripe::Payments::RefundService).not_to have_received(:call!)
    end

    it "logs that the provider is unsupported" do
      allow(Rails.logger).to receive(:info)

      service_result

      expect(Rails.logger).to have_received(:info)
        .with(a_string_matching(/PSP refund not supported.*CashfreeProvider/))
    end
  end
end
