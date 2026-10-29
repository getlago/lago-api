# frozen_string_literal: true

require "rails_helper"

describe "Operate a contract invoice through API v2" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "v2-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "v2-contract") }
  let(:customer_params) { {external_id: "v2-customer", email: "v2@example.com", timezone: "UTC", currency: "USD"} }
  let(:january) { Time.zone.parse("2027-01-01") }
  let(:february) { Time.zone.parse("2027-02-01") }

  around do |example|
    travel_to(Time.zone.parse("2026-12-31 12:00:00"))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer(customer_params)
    create_metric({name: "V2 usage", code: "v2-usage", aggregation_type: "sum_agg", field_name: "quantity"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "V2 usage", code: "v2-product", product_type: "metered", billable_metric_code: "v2-usage"
      }})
    end

    create_rate_card("v2-card", billing_timing: "arrears", display_on_invoice: true)
    create_plan_with_card("v2-plan", "v2-card")
    create_contract("v2-contract", "v2-plan")
    create_usage("v2-contract", Time.zone.parse("2027-01-10 12:00:00"), 80)
  end

  def create_rate_card(code, **attributes)
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: code, code:, product_code: "v2-product", currency: "USD", proration: false,
        rates: [{code: "r1", effective_from: january.iso8601, rate_model: "standard",
                 billing_interval_unit: "month", rate_properties: {amount: "1"}}],
        **attributes
      }})
    end
  end

  def create_plan_with_card(plan_code, rate_card_code)
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: plan_code, code: plan_code, currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/#{plan_code}/applied_rate_cards", {applied_rate_card: {rate_card_code:}})
    end
  end

  def create_contract(external_id, plan_code)
    travel_to(january + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          external_id:, external_customer_id: "v2-customer", plan_code:, started_at: january.iso8601
        }})
      end
    end
  end

  def create_usage(external_contract_id, at, quantity)
    travel_to(at) do
      create_event({external_contract_id:, code: "v2-usage", timestamp: at.to_i, properties: {"quantity" => quantity}})
    end
  end

  def tick(at)
    travel_to(at) do
      Clock::CreateBillingSegmentsJob.perform_now
      perform_all_enqueued_jobs
    end
  end

  context "with a finalized invoice" do
    let(:invoice) { customer.invoices.sole }

    before do
      tick(february + 12.minutes)
      travel_to(february + 1.day)
    end

    it "reads the invoice in the v2 shape, with its fees and contracts on request" do
      api_call { get_with_token(organization, "/api/v2/invoices/#{invoice.id}", {expands: %w[fees contracts]}) }

      expect(json[:invoice]).to include(
        lago_id: invoice.id, number: invoice.number, invoice_type: "contract", status: "finalized",
        payment_status: "pending", external_customer_id: "v2-customer", currency: "USD",
        fees_amount_cents: 8_000, total_amount_cents: 8_000
      )
      expect(json[:invoice][:contracts].sole).to include(lago_id: contract.id, external_id: "v2-contract")
      expect(json[:invoice][:fees].sole).to include(
        fee_type: "product", product_code: "v2-product", rate_card_code: "v2-card", rate_code: "r1",
        external_contract_id: "v2-contract", billing_timing: "arrears", units: "80.0", amount_cents: 8_000
      )
      expect(json[:invoice]).not_to have_key(:subscriptions)
    end

    it "returns the invoice once its pdf exists instead of generating it again" do
      expect(invoice.file).to be_attached

      api_call { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/download_pdf") }

      expect(json[:invoice]).to include(lago_id: invoice.id, invoice_type: "contract")
      expect(json[:invoice][:pdf_url]).to be_present
      expect(json[:invoice]).not_to have_key(:fees)
    end

    it "resends the invoice email", :premium do
      update_billing_entity(customer.billing_entity, {email: "billing@example.com"})

      expect { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/resend_email") }
        .to have_enqueued_mail(InvoiceMailer, :created)
        .with(params: {invoice:, resend: true, to: ["v2@example.com"], cc: [], bcc: []}, args: [])
      expect(response).to have_http_status(:success)
      expect(response.body).to be_empty
    end

    it "voids the invoice" do
      api_call { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/void") }

      expect(json[:invoice]).to include(lago_id: invoice.id, status: "voided", fees_amount_cents: 8_000)
      expect(json[:invoice][:voided_at]).to be_present
      expect(invoice.reload).to be_voided
    end

    context "with a Stripe customer" do
      let(:stripe_provider) { create(:stripe_provider, organization:, code: "stripe_1") }

      before do
        create(:stripe_customer, payment_provider: stripe_provider, customer:)
        customer.update!(payment_provider: :stripe, payment_provider_code: stripe_provider.code)
        allow(::Stripe::Checkout::Session).to receive(:create).and_return({"url" => "https://example.com/checkout"})
      end

      it "returns a payment url" do
        api_call { post_with_token(organization, "/api/v2/invoices/#{invoice.id}/payment_url") }

        expect(json[:payment_url]).to eq(
          lago_customer_id: customer.id,
          external_customer_id: "v2-customer",
          payment_provider: "stripe",
          lago_invoice_id: invoice.id,
          payment_url: "https://example.com/checkout"
        )
      end

      it "retries the payment through the provider" do
        post_with_token(organization, "/api/v2/invoices/#{invoice.id}/retry_payment")

        expect(response).to have_http_status(:success)
        expect(response.body).to be_empty
        expect(Invoices::Payments::CreateJob).to have_been_enqueued
          .with(invoice:, payment_provider: :stripe, payment_method_params: nil)
      end
    end
  end

  context "with a draft invoice", :premium do
    let(:customer_params) { super().merge(billing_configuration: {invoice_grace_period: 3}) }
    let(:invoice) { customer.invoices.sole }

    before do
      tick(february + 12.minutes)
      travel_to(february + 1.day)
    end

    it "refreshes the draft with late usage, then finalizes it" do
      expect(invoice).to be_draft
      expect(invoice.fees.sole).to have_attributes(units: 80, amount_cents: 8_000)

      create_usage("v2-contract", Time.zone.parse("2027-01-20 12:00:00"), 20)
      api_call { put_with_token(organization, "/api/v2/invoices/#{invoice.id}/refresh") }

      expect(json[:invoice]).to include(lago_id: invoice.id, status: "draft", fees_amount_cents: 10_000)
      expect(invoice.reload.fees.sole).to have_attributes(units: 100, amount_cents: 10_000)

      api_call { put_with_token(organization, "/api/v2/invoices/#{invoice.id}/finalize") }

      expect(json[:invoice]).to include(lago_id: invoice.id, status: "finalized", fees_amount_cents: 10_000)
      expect(json[:invoice][:number]).to be_present
      expect(invoice.reload).to have_attributes(status: "finalized", fees_amount_cents: 10_000)
    end
  end
end
