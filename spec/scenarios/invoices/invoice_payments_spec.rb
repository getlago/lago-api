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

  context "with Stripe and a currency Stripe reads in hundredths" do
    include_context "with Stripe configured for customer"

    let(:customer) { create(:customer, organization:, currency: "HUF", net_payment_term: 2, payment_term: {term_type: "net", days: 2}) }
    let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 50_000, amount_currency: "HUF") }
    let(:payment_intents_url) { "https://api.stripe.com/v1/payment_intents" }

    before do
      stub_request(:post, payment_intents_url)
        .and_return(
          status: 200,
          body: {
            id: "pi_huf",
            object: "payment_intent",
            status: "succeeded",
            amount: 5_000_000,
            currency: "huf"
          }.to_json
        )
      stub_request(:get, "https://api.stripe.com/v1/payment_methods/#{stripe_pm_id}")
        .and_return(status: 200, body: stripe_payment_method_response)
    end

    it "charges Stripe in hundredths and stores the payment in Lago units" do
      travel_to(DateTime.new(2025, 1, 1, 10)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan.code
          }
        )
        perform_billing
        perform_all_enqueued_jobs

        invoice = customer.invoices.sole
        expect(invoice.total_amount_cents).to eq(50_000)

        expect(
          a_request(:post, payment_intents_url)
            .with(body: hash_including("amount" => "5000000", "currency" => "huf")) # 50_000 HUF * 100
        ).to have_been_made.once

        payment = invoice.payments.sole
        expect(payment.provider_payment_id).to eq("pi_huf")
        expect(payment.amount_cents).to eq(50_000)
        expect(payment.amount_currency).to eq("HUF")

        invoice.reload
        expect(invoice.payment_status).to eq("succeeded")
        expect(invoice.total_paid_amount_cents).to eq(50_000)
      end
    end

    context "when the card is declined and the customer pays once through Stripe" do
      let(:stripe_provider) { create(:stripe_provider, organization:, settings: {webhook_secret: "whsec_huf"}) }
      let(:stripe_event_payload) do
        {
          id: "evt_huf_one_time",
          object: "event",
          created: Time.current.to_i,
          type: "payment_intent.succeeded",
          data: {
            object: {
              id: "pi_huf_one_time",
              object: "payment_intent",
              status: "succeeded",
              amount: 5_000_000, # what Stripe charged for 50_000 HUF
              currency: "huf",
              payment_method: stripe_pm_id,
              metadata: {
                lago_customer_id: customer.id,
                lago_invoice_id: customer.invoices.sole.id,
                invoice_issuing_date: customer.invoices.sole.issuing_date.iso8601,
                invoice_type: "subscription",
                payment_type: "one-time"
              }
            }
          }
        }.to_json
      end

      before do
        stub_request(:post, payment_intents_url)
          .and_return(
            status: 402,
            body: get_stripe_fixtures("payment_intent_card_declined_response.json")
          )
      end

      it "stores the one-time payment in Lago units" do
        travel_to(DateTime.new(2025, 1, 1, 10)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: external_subscription_id,
              plan_code: plan.code
            }
          )
          perform_billing
          perform_all_enqueued_jobs

          invoice = customer.invoices.sole
          expect(invoice.reload.payment_status).to eq("failed")

          signed_at = Time.current
          signature = ::Stripe::Webhook::Signature.compute_signature(signed_at, stripe_event_payload, stripe_provider.webhook_secret)
          post(
            "/webhooks/stripe/#{organization.id}?code=#{stripe_provider.code}",
            params: stripe_event_payload,
            headers: {
              "HTTP_STRIPE_SIGNATURE" => ::Stripe::Webhook::Signature.generate_header(signed_at, signature),
              "Content-Type" => "application/json"
            }
          )
          expect(response).to have_http_status(:ok)
          perform_all_enqueued_jobs

          payment = invoice.payments.find_by!(provider_payment_id: "pi_huf_one_time")
          expect(payment.amount_cents).to eq(50_000) # 5_000_000 / 100
          expect(payment.amount_currency).to eq("HUF")

          invoice.reload
          expect(invoice.payment_status).to eq("succeeded")
          expect(invoice.total_paid_amount_cents).to eq(50_000)
        end
      end
    end
  end

  context "with GoCardless refusing the payment" do
    let(:gocardless_provider) { create(:gocardless_provider, organization:) }
    let(:gocardless_customer) do
      create(:gocardless_customer, customer:, payment_provider: gocardless_provider, provider_customer_id: "CU123")
    end

    before do
      customer.update!(payment_provider: :gocardless, payment_provider_code: gocardless_provider.code)
      create(:payment_method, payment_provider_customer: gocardless_customer, provider_method_id: "MD123", is_default: true)

      stub_gocardless_error(:post, "/payments", status: 422, type: "validation_failed", message: "Validation failed")
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
