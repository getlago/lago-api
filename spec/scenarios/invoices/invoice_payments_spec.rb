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

  context "with Adyen" do
    let(:adyen_provider) { create(:adyen_provider, organization:) }
    let(:adyen_customer) do
      create(:adyen_customer, customer:, payment_provider: adyen_provider, provider_customer_id: "adyen_shopper_1")
    end
    let(:customer) do
      create(:customer, organization:, currency:, net_payment_term: 2, payment_term: {term_type: "net", days: 2})
    end
    let(:add_on) { create(:add_on, organization:, amount_cents:, amount_currency: currency) }

    let(:event_json) do
      fixture = JSON.parse(File.read(Rails.root.join("spec/fixtures/adyen/webhook_authorisation_payment_response.json")))
      event = fixture["notificationItems"].first["NotificationRequestItem"]
      event["pspReference"] = "psp_link_#{currency}"
      event["amount"] = {"currency" => currency, "value" => adyen_value}
      event["additionalData"]["metadata.lago_invoice_id"] = customer.invoices.sole.id
      event["additionalData"]["metadata.lago_customer_id"] = customer.id
      event["additionalData"]["metadata.payment_type"] = "one-time"
      event.to_json
    end

    before do
      customer.update!(payment_provider: :adyen, payment_provider_code: adyen_provider.code)
      adyen_customer
    end

    shared_examples "an Adyen payment in Adyen minor units" do
      context "with a default payment method" do
        before do
          create(:payment_method, payment_provider_customer: adyen_customer, provider_method_id: "adyen_pm_1", is_default: true)

          stub_adyen_checkout("paymentMethods", body: {storedPaymentMethods: [{id: "adyen_pm_1"}]})
          stub_adyen_checkout(
            "payments",
            body: {pspReference: "psp_1", resultCode: "Authorised", amount: {currency:, value: adyen_value}}
          )
        end

        it "charges the converted amount and records the invoice amount as paid" do
          travel_to(DateTime.new(2025, 1, 1, 10)) do
            create_one_off_invoice(customer, [add_on], currency:)

            invoice = customer.invoices.sole

            expect(WebMock).to have_requested(:post, %r{/payments\z}).with { JSON.parse(it.body).dig("amount", "value") == adyen_value }
            expect(invoice.total_amount_cents).to eq(amount_cents)
            expect(invoice.total_paid_amount_cents).to eq(amount_cents)
            expect(invoice.payment_status).to eq("succeeded")
          end
        end
      end

      context "without a payment method" do
        before do
          stub_adyen_checkout("payments", body: {pspReference: "psp_1", resultCode: "Authorised"})
          stub_adyen_checkout("paymentLinks", body: {url: "https://test.adyen.link/PL1", id: "PL1"})
        end

        it "sends the converted amount on the payment link and records the authorised amount in Lago units" do
          travel_to(DateTime.new(2025, 1, 1, 10)) do
            create_one_off_invoice(customer, [add_on], currency:)

            invoice = customer.invoices.sole
            expect(WebMock).not_to have_requested(:post, %r{/payments\z})
            expect(invoice.total_amount_cents).to eq(amount_cents)
            expect(invoice.payment_status).to eq("pending")

            post_with_token(organization, "/api/v1/invoices/#{invoice.id}/payment_url")

            expect(response).to have_http_status(:ok)
            expect(json[:invoice_payment_details][:payment_url]).to eq("https://test.adyen.link/PL1")
            expect(WebMock).to have_requested(:post, %r{/paymentLinks\z}).with { JSON.parse(it.body).dig("amount", "value") == adyen_value }

            PaymentProviders::Adyen::HandleEventJob.perform_now(organization:, event_json:)

            invoice.reload
            expect(invoice.payments.sole.amount_cents).to eq(amount_cents)
            expect(invoice.total_paid_amount_cents).to eq(amount_cents)
            expect(invoice.total_due_amount_cents).to eq(0)
            expect(invoice.payment_status).to eq("succeeded")
          end
        end
      end
    end

    context "with HUF, which Adyen counts in 2 decimals" do
      let(:currency) { "HUF" }
      let(:amount_cents) { 50_000 }
      let(:adyen_value) { 5_000_000 } # 50_000 * 100

      it_behaves_like "an Adyen payment in Adyen minor units"
    end

    context "with IDR, which Adyen counts in 0 decimals" do
      let(:currency) { "IDR" }
      let(:amount_cents) { 1_234_500 }
      let(:adyen_value) { 12_345 } # 1_234_500 / 100

      it_behaves_like "an Adyen payment in Adyen minor units"
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
