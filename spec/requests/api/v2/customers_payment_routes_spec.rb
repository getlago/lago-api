# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 customer payment routes" do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment_method) { create(:payment_method, customer:, organization:, is_default: false) }
  let(:payment) { create(:payment, payable: create(:invoice, organization:, customer:), customer:) }

  before { payment }

  it "lists the payments of the customer" do
    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payments")

    expect(response).to have_http_status(:success)
    expect(json[:payments].map { it[:lago_id] }).to eq([payment.id])
  end

  it "lists the payment methods of the customer" do
    payment_method

    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods")

    expect(response).to have_http_status(:success)
    expect(json[:payment_methods].map { it[:lago_id] }).to eq([payment_method.id])
  end

  it "sets a payment method as default" do
    put_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods/#{payment_method.id}/set_as_default")

    expect(response).to have_http_status(:success)
    expect(json[:payment_method]).to include(lago_id: payment_method.id, is_default: true)
  end

  it "deletes a payment method" do
    delete_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods/#{payment_method.id}")

    expect(response).to have_http_status(:success)
    expect(json[:payment_method][:lago_id]).to eq(payment_method.id)
    expect(payment_method.reload).to be_discarded
  end

  it "checks the page size as v1 does" do
    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payments", {per_page: 1_000_000_000})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json[:error_details]).to eq(per_page: ["value_is_out_of_range"])
  end

  it "answers 404 for an unknown customer" do
    get_with_token(organization, "/api/v2/customers/unknown/payments")

    expect(response).to be_not_found_error("customer")
  end

  it "refuses expands, as the payloads have no expansion" do
    get_with_token(organization, "/api/v2/customers/#{customer.external_id}/payment_methods", {expands: %w[customer]})

    expect(response).to have_http_status(:bad_request)
    expect(json[:error_details]).to eq(expands: {reason: "not_expandable", invalid_values: %w[customer]})
  end

  context "with a Stripe customer" do
    let(:stripe_provider) { create(:stripe_provider, organization:) }

    before do
      create(:stripe_customer, customer_id: customer.id, payment_provider: stripe_provider)
      customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)

      allow(::Stripe::Checkout::Session).to receive(:create)
        .and_return({"url" => "https://example.com"})
    end

    it "generates a checkout url" do
      post_with_token(organization, "/api/v2/customers/#{customer.external_id}/checkout_url")

      expect(response).to have_http_status(:success)
      expect(json[:customer][:checkout_url]).to eq("https://example.com")
    end
  end

  describe "API key permissions" do
    let(:customer_path) { "/api/v2/customers/#{customer.external_id}" }

    describe "GET payments" do
      subject { get_with_token(organization, "#{customer_path}/payments") }

      include_examples "requires API permission", "payment", "read"
    end

    describe "GET payment_methods" do
      subject { get_with_token(organization, "#{customer_path}/payment_methods") }

      include_examples "requires API permission", "payment_method", "read"
    end

    describe "PUT payment_methods/:id/set_as_default" do
      subject { put_with_token(organization, "#{customer_path}/payment_methods/#{payment_method.id}/set_as_default") }

      include_examples "requires API permission", "payment_method", "write"
    end

    describe "DELETE payment_methods/:id" do
      subject { delete_with_token(organization, "#{customer_path}/payment_methods/#{payment_method.id}") }

      include_examples "requires API permission", "payment_method", "write"
    end

    describe "POST checkout_url" do
      subject { post_with_token(organization, "#{customer_path}/checkout_url") }

      include_examples "requires API permission", "customer", "write"
    end
  end

  context "when the organization is not on the product catalog", product_catalog: false do
    {
      get: ["payments", "payment_methods"],
      put: ["payment_methods/:payment_method_id/set_as_default"],
      delete: ["payment_methods/:payment_method_id"],
      post: ["checkout_url"]
    }.each do |method, paths|
      paths.each do |path|
        it "answers 403 to #{method.upcase} #{path}" do
          public_send(:"#{method}_with_token", organization, "/api/v2/customers/#{customer.external_id}/#{path.sub(":payment_method_id", payment_method.id)}")

          expect(response).to have_http_status(:forbidden)
          expect(json[:code]).to eq("feature_unavailable")
        end
      end
    end
  end
end
