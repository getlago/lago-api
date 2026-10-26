# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::SetPaymentMethodAndCreateReceiptJob do
  before_all do
    create_default(:organization)
    create_default(:invoice)
  end

  let(:payment) { create(:payment) }
  let(:provider_payment_method_id) { "pm_001" }

  before do
    allow(Payments::SetPaymentMethodDataService)
      .to receive(:call!).with(payment:, provider_payment_method_id:).and_return(Payments::SetPaymentMethodDataService::Result.new)
  end

  it "calls the service" do
    described_class.perform_now(payment:, provider_payment_method_id:)

    expect(Payments::SetPaymentMethodDataService).to have_received(:call!)
  end

  context "with customer payment_method" do
    let(:customer) { payment.customer }
    let(:payment_method) { create(:payment_method, customer:, provider_method_id: provider_payment_method_id) }

    before { payment_method }

    it "attachs the payment method to the payment" do
      described_class.perform_now(payment:, provider_payment_method_id:)
      expect(payment.payment_method_id).to eq(payment_method.id)
    end
  end

  context "when the Stripe payment method is attached to the customer's Stripe customer and unknown to Lago" do
    # The fixture payment method belongs to this Stripe customer, as a card saved through a payment link does.
    let(:provider_payment_method_id) { "pm_1RTjuYQ8iJWBZFaMCfXmSmQD" }
    let(:customer) { create(:customer) }
    let(:stripe_customer) { create(:stripe_customer, customer:, provider_customer_id: "cus_SOWyVXSNy6uKcg") }
    let(:payment) { create(:payment, payable: create(:invoice, customer:), payment_provider_customer: stripe_customer) }

    before do
      allow(Payments::SetPaymentMethodDataService).to receive(:call!).and_call_original

      stub_request(:get, %r{/v1/payment_methods/#{provider_payment_method_id}}).and_return(
        status: 200, body: get_stripe_fixtures("retrieve_payment_method_response.json", version: "2025-04-30.basil")
      )
    end

    it "creates a default payment method with the card details and links it to the payment" do
      described_class.perform_now(payment:, provider_payment_method_id:)

      payment_method = customer.payment_methods.sole
      expect(payment_method).to have_attributes(
        provider_method_id: provider_payment_method_id,
        payment_provider_customer: stripe_customer,
        is_default: true,
        details: hash_including("type" => "card", "brand" => "visa", "last4" => "4242")
      )
      expect(payment.reload.payment_method_id).to eq(payment_method.id)
    end
  end
end
