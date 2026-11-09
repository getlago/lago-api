# frozen_string_literal: true

require "rails_helper"

describe "Invoice Payments Scenarios" do
  let(:webhook_url) { "https://test.co/lago" }
  let(:organization) do
    create(:organization,
      name: "JC AI",
      premium_integrations: %w[auto_dunning],
      email_settings: [],
      webhook_url:)
  end

  let(:external_subscription_id) { "sub_payment-failed" }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 149_00) }

  let(:webhooks_sent) { [] }

  let(:customer) { create(:customer, organization:, net_payment_term: 2, payment_term: {term_type: "net", days: 2}) }

  before do
    stub_pdf_generation

    stub_request(:post, webhook_url).with do |req|
      webhooks_sent << JSON.parse(req.body.dup)
      true
    end.and_return(status: 200)
  end

  context "with Stripe" do
    include_context "with Stripe configured for customer"

    before do
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .and_return(
          status: 402,
          body: get_stripe_fixtures("payment_intent_card_declined_response.json")
        )
    end

    it "retries overdue invoices" do
      travel_to(DateTime.new(2025, 1, 1, 10)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan.code
          }
        )
        perform_billing

        payment_failure_webhook = webhooks_sent.find { it["webhook_type"] == "invoice.payment_failure" }

        expect(payment_failure_webhook["payment_provider_invoice_payment_error"]["error_details"]).to include({
          "code" => "card_declined",
          "message" => "Your card was declined."
        })
      end
    end
  end

  context "with GoCardless refusing the payment" do
    let(:gocardless_provider) { create(:gocardless_provider, organization:) }
    let(:gocardless_customer) do
      create(:gocardless_customer, customer:, payment_provider: gocardless_provider, provider_customer_id: "CU123")
    end

    let(:gocardless_validation_error_body) do
      {
        error: {
          type: "validation_failed",
          code: 422,
          message: "Validation failed",
          errors: [{field: "amount", message: "is invalid"}],
          documentation_url: "https://developer.gocardless.com/api-reference#validation_failed",
          request_id: "req_123"
        }
      }.to_json
    end

    before do
      customer.update!(payment_provider: :gocardless, payment_provider_code: gocardless_provider.code)
      create(:payment_method, payment_provider_customer: gocardless_customer, provider_method_id: "MD123", is_default: true)

      stub_request(:post, "https://api-sandbox.gocardless.com/payments")
        .and_return(status: 422, body: gocardless_validation_error_body, headers: {"Content-Type" => "application/json"})
    end

    it "marks the invoice as failed and sends one payment failure webhook" do
      travel_to(DateTime.new(2025, 1, 1, 10)) do
        expect do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
        end.not_to raise_error

        invoice = customer.invoices.sole
        get_with_token(organization, "/api/v1/invoices/#{invoice.id}")

        expect(response).to have_http_status(:ok)
        expect(json[:invoice][:payment_status]).to eq("failed")
        expect(webhooks_sent.count { it["webhook_type"] == "invoice.payment_failure" }).to eq(1)
      end
    end
  end
end
