# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::PaystackService do
  subject(:service) { described_class.new(paystack_customer) }

  let(:organization) { create(:organization) }
  let(:payment_provider) { create(:paystack_provider, organization:) }
  let(:customer) { create(:customer, organization:, email: "customer@example.com", currency: "NGN") }
  let(:paystack_customer) do
    create(:paystack_customer, customer:, organization:, payment_provider:, provider_customer_id: "CUS_test")
  end

  describe "constants" do
    it "defines an authorization amount for every Paystack-supported setup currency" do
      expect(described_class::AUTHORIZATION_AMOUNTS_CENTS.keys)
        .to match_array(PaymentProviders::PaystackProvider::SUPPORTED_CURRENCIES)
    end
  end

  describe "#generate_checkout_url" do
    let(:client) { instance_double(PaymentProviders::Paystack::Client) }

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
      allow(client).to receive(:initialize_transaction).and_return(
        "data" => {"authorization_url" => "https://checkout.paystack.com/test"}
      )
    end

    it "initializes a card-only setup transaction" do
      result = service.generate_checkout_url(send_webhook: false)

      expect(result).to be_success
      expect(result.checkout_url).to eq("https://checkout.paystack.com/test")
      expect(client).to have_received(:initialize_transaction) do |payload|
        metadata = JSON.parse(payload[:metadata])

        expect(payload[:channels]).to eq(["card"])
        expect(payload[:amount]).to eq(5000)
        expect(payload[:currency]).to eq("NGN")
        expect(metadata).to include(
          "lago_customer_id" => customer.id,
          "lago_paystack_customer_id" => paystack_customer.id,
          "payment_type" => "setup"
        )
      end
    end

    context "when currency is unsupported" do
      let(:customer) { create(:customer, organization:, email: "customer@example.com", currency: "EUR") }

      it "returns a validation failure without calling Paystack" do
        result = service.generate_checkout_url(send_webhook: false)

        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["unsupported_currency"])
        expect(client).not_to have_received(:initialize_transaction)
      end
    end
  end

  describe "#update_payment_method" do
    let(:payment_method_id) { "AUTH_test" }

    it "stores the reusable authorization on the provider customer" do
      result = service.update_payment_method(
        organization_id: organization.id,
        customer_id: customer.id,
        payment_method_id:,
        metadata: {"lago_customer_id" => customer.id}
      )

      expect(result).to be_success
      expect(paystack_customer.reload.authorization_code).to eq(payment_method_id)
      expect(paystack_customer.payment_method_id).to eq(payment_method_id)
    end

    context "when multiple payment methods are enabled" do
      before { organization.update!(feature_flags: ["multiple_payment_methods"]) }

      it "creates the default payment method with card details" do
        result = service.update_payment_method(
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
