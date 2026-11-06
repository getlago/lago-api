# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::Customers::CheckoutUrlsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }

  describe "POST /api/v2/customers/:external_id/checkout_url" do
    subject { post_with_token(organization, "/api/v2/customers/#{customer.external_id}/checkout_url") }

    include_examples "requires API permission", "customer", "write"

    context "with a Stripe customer" do
      let(:stripe_provider) { create(:stripe_provider, organization:) }

      before do
        create(:stripe_customer, customer_id: customer.id, payment_provider: stripe_provider)
        customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

        allow(::Stripe::Checkout::Session).to receive(:create).and_return({"url" => "https://example.com"})
      end

      it "returns the checkout url with the v2 payload" do
        subject

        expect(response).to have_http_status(:success)
        expect(json).to eq(
          checkout_url: {
            lago_customer_id: customer.id,
            external_customer_id: customer.external_id,
            payment_provider: "stripe",
            payment_provider_code: stripe_provider.code,
            checkout_url: "https://example.com"
          }
        )
      end
    end

    context "when Adyen refuses the payment link" do
      let(:adyen_provider) { create(:adyen_provider, organization:) }
      let(:adyen_client) { instance_double(Adyen::Client) }
      let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
      let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }

      before do
        create(:adyen_customer, customer:, payment_provider: adyen_provider)
        customer.update!(payment_provider: "adyen", payment_provider_code: adyen_provider.code)

        allow(Adyen::Client).to receive(:new).and_return(adyen_client)
        allow(adyen_client).to receive(:checkout).and_return(checkout)
        allow(checkout).to receive(:payment_links_api).and_return(payment_links_api)
        allow(payment_links_api).to receive(:payment_links).and_return(generate(:adyen_payment_links_error_response))
      end

      it "returns a provider error naming the provider" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(
          code: "provider_error",
          details: [{code: "provider_error", field: "base", meta: {provider_name: "adyen", provider_error_code: "validation"}}]
        )
      end
    end

    context "when GoCardless refuses the billing request" do
      let(:gocardless_provider) { create(:gocardless_provider, organization:) }

      before do
        create(:gocardless_customer, customer:, payment_provider: gocardless_provider, provider_customer_id: nil)
        customer.update!(payment_provider: "gocardless", payment_provider_code: gocardless_provider.code)

        allow(GoCardlessPro::Client).to receive(:new)
          .and_raise(GoCardlessPro::InvalidApiUsageError.new("message" => "Customer not found", "code" => 422))
      end

      it "returns a provider error naming the provider" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to eq(code: "provider_error", details: [{code: "provider_error", field: "base", meta: {provider_name: "gocardless"}}])
      end
    end

    context "without a payment provider" do
      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "when the organization is not on the product catalog", product_catalog: false do
      let(:organization) { create(:organization) }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
