# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::PaystackService do
  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:paystack_provider, organization:) }
  let(:customer) { create(:customer, organization:, email: "customer@example.com", currency: "NGN") }
  let(:paystack_customer) do
    create(:paystack_customer, customer:, organization:, payment_provider:, provider_customer_id: "CUS_test")
  end

  describe "#generate_checkout_url" do
    subject(:result) { described_class.call(:generate_checkout_url, paystack_customer, send_webhook:) }

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_call_original
    end

    [true, false].each do |send_webhook|
      context "with send_webhook set to #{send_webhook}" do
        let(:send_webhook) { send_webhook }

        it "returns an unsupported feature error without requesting checkout or sending a webhook" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("feature_not_supported")
          expect(PaymentProviders::Paystack::Client).not_to have_received(:new)
          expect(SendWebhookJob).not_to have_been_enqueued.with("customer.checkout_url_generated", customer, anything)
        end
      end
    end
  end

  describe "#update_payment_method" do
    let(:payment_method_id) { "AUTH_test" }

    before { paystack_customer }

    it "stores the reusable authorization on the provider customer" do
      result = described_class.call(
        :update_payment_method,
        organization_id: organization.id,
        customer_id: customer.id,
        payment_method_id:,
        metadata: {"lago_customer_id" => customer.id}
      )

      expect(result).to be_success
      expect(paystack_customer.reload.authorization_code).to eq(payment_method_id)
      expect(paystack_customer.payment_method_id).to eq(payment_method_id)
    end

    context "with card details" do
      it "creates the default payment method with card details" do
        result = described_class.call(
          :update_payment_method,
          organization_id: organization.id,
          customer_id: customer.id,
          payment_method_id:,
          metadata: {"lago_customer_id" => customer.id},
          card_details: {
            brand: "visa",
            last4: "4081",
            expiration_month: "12",
            expiration_year: "2030"
          }
        )

        expect(result).to be_success
        expect(result.payment_method).to have_attributes(
          customer:,
          payment_provider_customer: paystack_customer,
          provider_method_id: payment_method_id,
          provider_method_type: "card",
          is_default: true
        )
        expect(result.payment_method.details).to include(
          "brand" => "visa",
          "last4" => "4081",
          "expiration_month" => "12",
          "expiration_year" => "2030"
        )
      end
    end
  end
end
