# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Customers::FetchDefaultPaymentMethodService do
  subject(:service) { described_class.new(provider_customer:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:provider_customer_id) { "cus_123456" }
  let(:provider_customer) do
    create(
      :stripe_customer,
      customer:,
      provider_customer_id:,
      payment_provider: stripe_provider,
      provider_payment_methods: %w[card]
    )
  end

  describe "#call" do
    let(:payment_method_id) { "pm_123456" }
    let(:retrieve_service_result) do
      PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService::Result.new.tap do |r|
        r.payment_method_id = payment_method_id
      end
    end

    before do
      allow(PaymentProviderCustomers::Stripe::RetrieveLatestPaymentMethodService)
        .to receive(:call!)
        .with(provider_customer:)
        .and_return(retrieve_service_result)
    end

    context "when provider_customer has no provider_customer_id" do
      let(:provider_customer_id) { nil }

      it "returns result without creating payment method" do
        result = service.call

        expect(result).to be_success
        expect(PaymentMethods::CreateFromProviderService).not_to receive(:call)
      end
    end

    context "when no payment method is found on Stripe" do
      let(:payment_method_id) { nil }

      it "returns result without creating payment method" do
        result = service.call

        expect(result).to be_success
        expect(PaymentMethods::CreateFromProviderService).not_to receive(:call)
      end
    end

    context "when payment method is found on Stripe" do
      let(:stripe_payment_method) do
        Stripe::PaymentMethod.construct_from(
          id: payment_method_id,
          type: "card",
          card: {
            last4: "4242",
            display_brand: "visa",
            exp_month: 12,
            exp_year: 2025
          }
        )
      end

      before do
        allow(Stripe::PaymentMethod)
          .to receive(:retrieve)
          .with(payment_method_id, {api_key: stripe_provider.secret_key})
          .and_return(stripe_payment_method)
      end

      it "creates a payment method in Lago with details" do
        result = service.call

        payment_method = customer.payment_methods.order(created_at: :desc).first

        expect(result).to be_success
        expect(payment_method.provider_method_id).to eq(payment_method_id)
      end
    end
  end
end
