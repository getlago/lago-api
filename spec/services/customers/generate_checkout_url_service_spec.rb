# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::GenerateCheckoutUrlService do
  subject(:generate_checkout_url_service) { described_class.new(customer:) }

  let_it_be(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }

  describe ".call" do
    let(:stripe_provider) { create(:stripe_provider, organization:) }

    context "when payment provider is linked" do
      before do
        create(
          :stripe_customer,
          customer_id: customer.id,
          payment_provider: stripe_provider
        )

        customer.update(payment_provider: "stripe")

        allow(PaymentProviderCustomers::StripeService).to receive(:call)
          .with(:generate_checkout_url, anything, send_webhook: false)
          .and_return(BaseResult[:checkout_url].new.tap { |r| r.checkout_url = "http://foo.bar" })
      end

      it "returns the generated checkout url" do
        result = generate_checkout_url_service.call

        expect(result.checkout_url).to eq("http://foo.bar")
      end
    end

    context "when Adyen raises what the checkout URL job retries on" do
      let(:adyen_provider) { create(:adyen_provider, organization:) }

      before do
        create(:adyen_customer, customer:, payment_provider: adyen_provider)
        customer.update!(payment_provider: "adyen", payment_provider_code: adyen_provider.code)

        allow(PaymentProviderCustomers::AdyenService).to receive(:call)
          .and_raise(Adyen::AuthenticationError.new("Unauthorized", nil))
      end

      it "returns a third-party failure" do
        result = generate_checkout_url_service.call

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "Adyen", error_code: 401, error_message: "Unauthorized")
      end
    end

    context "when GoCardless refuses the billing request" do
      let(:gocardless_provider) { create(:gocardless_provider, organization:) }

      before do
        create(:gocardless_customer, customer:, payment_provider: gocardless_provider)
        customer.update!(payment_provider: "gocardless", payment_provider_code: gocardless_provider.code)

        allow(PaymentProviderCustomers::GocardlessService).to receive(:call)
          .and_raise(GoCardlessPro::InvalidApiUsageError.new("message" => "Customer not found", "code" => 422))
      end

      it "returns a third-party failure" do
        result = generate_checkout_url_service.call

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "GoCardless", error_code: 422, error_message: "Customer not found")
      end
    end

    context "when Stripe cannot be reached" do
      before do
        create(:stripe_customer, customer:, payment_provider: stripe_provider)
        customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

        allow(PaymentProviderCustomers::StripeService).to receive(:call)
          .and_raise(Stripe::APIConnectionError.new("Connection refused"))
      end

      it "returns a third-party failure" do
        result = generate_checkout_url_service.call

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error).to have_attributes(third_party: "Stripe", error_code: nil, error_message: "Connection refused")
      end
    end

    context "when customer is blank" do
      it "returns an error" do
        result = described_class.new(customer: nil).call

        expect(result).not_to be_success
        expect(result.error.message).to eq("customer_not_found")
      end
    end

    context "when payment provider is blank" do
      it "returns an error" do
        result = generate_checkout_url_service.call

        expect(result).not_to be_success
      end
    end
  end
end
