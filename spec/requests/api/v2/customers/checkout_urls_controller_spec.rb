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
