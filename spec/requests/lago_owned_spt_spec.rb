# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lago-owned shared payment tokens", type: :request do
  let(:organization) { create(:organization) }
  let(:provider) { create(:stripe_provider, organization:, code: "spt_local") }
  let(:customer) { create(:customer, organization:, payment_provider: "stripe", payment_provider_code: provider.code) }
  let(:token) { "spt_localtest" }
  let(:stripe_customer) do
    create(:stripe_customer, customer:, payment_provider: provider, provider_payment_methods: ["card"],
      default_shared_payment_token: token)
  end

  describe "customer configuration" do
    it "stores the token through the API without exposing it in customer responses" do
      post_with_token(organization, "/api/v1/customers", customer: {
        external_id: "spt_api_customer", currency: "USD",
        billing_configuration: {payment_provider: "stripe", payment_provider_code: provider.code,
                                provider_customer_id: "cus_api", default_shared_payment_token: token}
      })

      expect(response).to have_http_status(:ok)
      stored = organization.customers.find_by!(external_id: "spt_api_customer").stripe_customer
      expect(stored.default_shared_payment_token).to eq(token)
      expect(json[:customer][:billing_configuration][:has_shared_payment_token]).to be(true)
      expect(json[:customer][:billing_configuration]).not_to have_key(:default_shared_payment_token)
    end

    it "preserves the token when omitted and clears it when explicitly null" do
      stripe_customer
      service = PaymentProviders::Stripe::Customers::CreateService
      result = service.call(customer:, payment_provider_id: provider.id, params: {})
      expect(result).to be_success
      expect(stripe_customer.reload.default_shared_payment_token).to eq(token)

      result = service.call(customer:, payment_provider_id: provider.id, params: {default_shared_payment_token: nil})
      expect(result).to be_success
      expect(stripe_customer.reload.default_shared_payment_token).to be_nil
    end

    it "rejects a PaymentMethod ID as an SPT" do
      stripe_customer.default_shared_payment_token = "pm_not_a_token"
      expect(stripe_customer).not_to be_valid
      expect(stripe_customer.errors[:default_shared_payment_token]).to be_present
    end

    it "rejects a token with a bank-transfer-only connection" do
      stripe_customer.provider_payment_methods = ["customer_balance"]
      expect(stripe_customer).not_to be_valid
      expect(stripe_customer.errors[:default_shared_payment_token]).to be_present
    end
  end

  describe "native invoice collection" do
    let(:invoice) do
      create(:invoice, organization:, customer:, invoice_type: :one_off,
        total_amount_cents: 100, currency: "USD", ready_for_payment_processing: true)
    end
    let(:stripe_default) { nil }
    let(:stripe_status) { 200 }
    let(:stripe_body) { {id: "pi_spt_test", status: "succeeded", amount: 100, currency: "usd"} }

    before do
      stripe_customer
      stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
        .to_return(body: {id: stripe_customer.provider_customer_id, object: "customer",
                          invoice_settings: {default_payment_method: stripe_default}, default_source: nil}.to_json)
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .with(body: hash_including("amount" => "100", "currency" => "usd",
          "payment_method_data" => {"shared_payment_granted_token" => token}))
        .to_return(status: stripe_status, body: stripe_body.to_json)
    end

    it "collects an invoice for a token-only customer and reconciles the native payment" do
      result = Invoices::Payments::CreateService.call(invoice:)

      expect(result).to be_success
      expect(invoice.reload.payment_status).to eq("succeeded")
      expect(invoice.total_paid_amount_cents).to eq(100)
      expect(invoice.payments.sole.provider_payment_id).to eq("pi_spt_test")
      expect(stripe_customer.reload.default_shared_payment_token).to eq(token)
    end

    context "with an existing Stripe default card" do
      let(:stripe_default) { "pm_existing_card" }

      it "still submits only the SPT" do
        Invoices::Payments::CreateService.call(invoice:)

        expect(invoice.reload.payment_status).to eq("succeeded")
        expect(WebMock).to have_requested(:post, "https://api.stripe.com/v1/payment_intents")
          .with { |request| !Rack::Utils.parse_nested_query(request.body).key?("payment_method") }.once
      end
    end

    context "when Stripe rejects the token" do
      let(:stripe_default) { "pm_existing_card" }
      let(:stripe_status) { 400 }
      let(:stripe_body) { {error: {type: "invalid_request_error", code: "resource_missing", message: "Token deactivated"}} }

      it "fails the invoice without retrying with the card or clearing the token" do
        Invoices::Payments::CreateService.call(invoice:)

        expect(invoice.reload.payment_status).to eq("failed")
        expect(invoice.total_paid_amount_cents).to eq(0)
        expect(invoice.payments.sole.status).to eq("failed")
        expect(stripe_customer.reload.default_shared_payment_token).to eq(token)
        expect(WebMock).to have_requested(:post, "https://api.stripe.com/v1/payment_intents").once
      end
    end
  end
end
