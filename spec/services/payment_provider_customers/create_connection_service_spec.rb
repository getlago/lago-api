# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviderCustomers::CreateConnectionService do
  subject(:create_service) { described_class.new(customer:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_eu") }
  let(:params) { {payment_provider: "stripe", provider_customer_id: "cus_123"} }

  before { stripe_provider }

  describe "#call" do
    subject(:result) { create_service.call }

    context "when customer is not found" do
      let(:customer) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when payment provider is missing" do
      let(:params) { {code: "stripe_eu", provider_customer_id: "cus_123"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:payment_provider]).to eq(["value_is_mandatory"])
      end
    end

    context "when neither provider_customer_id nor sync_with_provider is given" do
      let(:params) { {payment_provider: "stripe", code: "stripe_eu_connection"} }

      it "returns a successful result without a payment provider customer" do
        expect(result).to be_success
        expect(result.payment_provider_customer).to be_nil
      end

      it "does not create the payment provider customer" do
        expect { create_service.call }.not_to change(PaymentProviderCustomers::StripeCustomer, :count)
      end

      it "does not change the customer payment provider settings" do
        expect { create_service.call }.not_to change { customer.reload.payment_provider }
      end
    end

    context "when the payment provider does not exist" do
      let(:params) { {payment_provider: "adyen", provider_customer_id: "cus_123"} }

      it "returns a service failure" do
        expect(result).not_to be_success
        expect(result.error.code).to eq("payment_provider_not_found")
      end
    end

    context "with a valid payment provider" do
      let(:params) do
        {
          payment_provider: "stripe",
          payment_provider_code: "stripe_eu",
          code: "stripe_eu_connection",
          provider_customer_id: "cus_123",
          provider_payment_methods: %w[card sepa_debit]
        }
      end

      it "creates the payment provider customer" do
        expect { create_service.call }.to change(PaymentProviderCustomers::StripeCustomer, :count).by(1)
      end

      it "returns the payment provider customer with its attributes" do
        payment_provider_customer = result.payment_provider_customer

        expect(result).to be_success
        expect(payment_provider_customer).to be_a(PaymentProviderCustomers::StripeCustomer)
        expect(payment_provider_customer.code).to eq("stripe_eu_connection")
        expect(payment_provider_customer.payment_provider).to eq(stripe_provider)
        expect(payment_provider_customer.provider_customer_id).to eq("cus_123")
        expect(payment_provider_customer.provider_payment_methods).to match_array(%w[card sepa_debit])
      end

      it "marks the first connection as the default one" do
        expect(result.payment_provider_customer).to be_is_default
      end

      it "sets the customer payment provider settings" do
        create_service.call

        expect(customer.reload.payment_provider).to eq("stripe")
        expect(customer.payment_provider_code).to eq("stripe_eu")
      end
    end

    context "when no code is given" do
      let(:params) do
        {payment_provider: "stripe", payment_provider_code: "stripe_eu", provider_customer_id: "cus_123"}
      end

      it "derives the code from the payment provider" do
        expect(result).to be_success
        expect(result.payment_provider_customer.code).to eq("stripe_eu")
      end
    end

    context "when the organization has several providers of the same type" do
      let(:stripe_us_provider) { create(:stripe_provider, organization:, code: "stripe_us") }
      let(:params) do
        {payment_provider: "stripe", payment_provider_code: "stripe_us", provider_customer_id: "cus_123"}
      end

      before { stripe_us_provider }

      it "attaches the connection to the requested provider" do
        expect(result).to be_success
        expect(result.payment_provider_customer.payment_provider).to eq(stripe_us_provider)
      end

      context "when the payment provider code is not given" do
        let(:params) { {payment_provider: "stripe", provider_customer_id: "cus_123"} }

        it "cannot resolve which provider to connect to" do
          expect(result).not_to be_success
          expect(result.error.code).to eq("payment_provider_code_missing")
        end
      end
    end

    context "when the customer already has a connection" do
      let(:existing_connection) { create(:adyen_customer, organization:, customer:, is_default: true) }
      let(:params) { {payment_provider: "stripe", code: "stripe_eu_connection", provider_customer_id: "cus_123"} }

      before { existing_connection }

      it "does not mark the new connection as the default one" do
        expect(result.payment_provider_customer).not_to be_is_default
      end

      it "leaves the existing default untouched" do
        expect { create_service.call }.not_to change { existing_connection.reload.is_default }
      end

      it "does not change the customer payment provider settings" do
        expect { create_service.call }.not_to change { customer.reload.payment_provider }
      end
    end

    context "when the customer already has payment provider settings" do
      let(:customer) do
        create(:customer, organization:, payment_provider: "adyen", payment_provider_code: "adyen_legacy")
      end
      let(:params) { {payment_provider: "stripe", code: "stripe_eu_connection", provider_customer_id: "cus_123"} }

      it "does not overwrite them" do
        create_service.call

        expect(customer.reload.payment_provider).to eq("adyen")
        expect(customer.payment_provider_code).to eq("adyen_legacy")
      end

      it "still creates the connection as the default one" do
        expect(result).to be_success
        expect(result.payment_provider_customer).to be_is_default
      end
    end

    context "when the code is already used by another connection of the customer" do
      let(:params) { {payment_provider: "stripe", code: "duplicated_code", provider_customer_id: "cus_123"} }

      before { create(:adyen_customer, organization:, customer:, code: "duplicated_code") }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end

      it "does not create the payment provider customer" do
        expect { create_service.call }.not_to change(PaymentProviderCustomers::StripeCustomer, :count)
      end
    end

    context "when sync_with_provider is true" do
      let(:params) { {payment_provider: "stripe", sync_with_provider: true} }

      it "enqueues a job to create the customer on the provider" do
        create_service.call

        expect(PaymentProviderCustomers::StripeCreateJob).to have_been_enqueued
      end
    end
  end
end
