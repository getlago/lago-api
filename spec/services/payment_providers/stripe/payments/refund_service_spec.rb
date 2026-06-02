# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::RefundService do
  subject(:service_result) { described_class.call(payment:, reason:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, status: :closed) }
  let(:reason) { :subscription_activation_expired }
  let(:payment_provider) { create(:stripe_provider, organization:, secret_key: "sk_test_123") }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider:) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: stripe_customer,
      organization:,
      customer:,
      provider_payment_id: "pi_test_123",
      payable_payment_status: :succeeded,
      amount_cents: 25_00,
      amount_currency: "EUR"
    )
  end

  before do
    allow(::Stripe::Refund).to receive(:create)
      .and_return(
        ::Stripe::Refund.construct_from(
          id: "re_123456",
          status: "succeeded",
          amount: 25_00,
          currency: "eur"
        )
      )
  end

  it "calls Stripe with the full payment amount and Lago payment metadata" do
    service_result

    expect(::Stripe::Refund).to have_received(:create).with(
      {
        payment_intent: "pi_test_123",
        amount: 25_00,
        reason: :requested_by_customer,
        metadata: {
          lago_customer_id: customer.id,
          lago_refundable_id: invoice.id,
          lago_refundable_type: "Invoice",
          lago_payment_id: payment.id,
          lago_refund_reason: "subscription_activation_expired"
        }
      },
      {
        api_key: "sk_test_123",
        idempotency_key: "payment-refund-#{payment.id}"
      }
    )
  end

  it "creates a payment refund row" do
    expect { service_result }.to change(Refund, :count).by(1)

    refund = service_result.refund
    expect(refund.credit_note).to be_nil
    expect(refund.refundable).to eq(invoice)
    expect(refund.reason).to eq("subscription_activation_expired")
    expect(refund.payment).to eq(payment)
    expect(refund.payment_provider).to eq(payment_provider)
    expect(refund.payment_provider_customer).to eq(stripe_customer)
    expect(refund.amount_cents).to eq(25_00)
    expect(refund.amount_currency).to eq("EUR")
    expect(refund.status).to eq("succeeded")
    expect(refund.provider_refund_id).to eq("re_123456")
  end

  it "returns the payment and refund" do
    expect(service_result).to be_success
    expect(service_result.payment).to eq(payment)
    expect(service_result.refund).to be_a(Refund)
  end

  context "when no Lago refund reason is provided" do
    let(:reason) { nil }

    it "creates a refund without a reason" do
      service_result

      expect(service_result.refund.reason).to be_nil
    end

    it "does not send an empty refund reason in Stripe metadata" do
      service_result

      expect(::Stripe::Refund).to have_received(:create).with(
        hash_including(metadata: hash_excluding(:lago_refund_reason)),
        anything
      )
    end
  end

  context "when Stripe rejects the refund request" do
    before do
      allow(::Stripe::Refund).to receive(:create)
        .and_raise(
          ::Stripe::InvalidRequestError.new(
            "Charge has already been refunded",
            "payment_intent",
            code: "charge_already_refunded"
          )
        )
    end

    it "creates a failed payment refund row" do
      expect { service_result }.to change(Refund, :count).by(1)

      refund = service_result.refund
      expect(refund.credit_note).to be_nil
      expect(refund.refundable).to eq(invoice)
      expect(refund.reason).to eq("subscription_activation_expired")
      expect(refund.payment).to eq(payment)
      expect(refund.amount_cents).to eq(25_00)
      expect(refund.amount_currency).to eq("EUR")
      expect(refund.status).to eq("failed")
      expect(refund.provider_refund_id).to eq("payment-refund-#{payment.id}")
    end

    it "returns a service failure with the Stripe error" do
      expect(service_result).to be_failure
      expect(service_result.error).to be_a(BaseService::ServiceFailure)
      expect(service_result.error.code).to eq("stripe_error")
      expect(service_result.error.error_message).to eq("Charge has already been refunded")
    end
  end

  context "when Stripe returns a transient error" do
    before do
      allow(::Stripe::Refund).to receive(:create)
        .and_raise(::Stripe::APIConnectionError.new("network error"))
    end

    it "propagates the error so Sidekiq can retry" do
      expect { service_result }.to raise_error(::Stripe::APIConnectionError)
      expect(Refund.where(payment:, reason: :subscription_activation_expired)).not_to exist
    end
  end
end
