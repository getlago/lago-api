# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::GocardlessService, type: :service do
  subject(:gocardless_service) { described_class.new(payment_request) }

  let(:organization) { create(:organization, webhook_url: "https://webhook.com") }
  let(:customer) { create(:customer, organization:, payment_provider_code: code) }
  let(:gocardless_payment_provider) { create(:gocardless_provider, organization:, code:) }
  let(:gocardless_customer) { create(:gocardless_customer, customer:) }
  let(:gocardless_client) { instance_double(GoCardlessPro::Client) }
  let(:gocardless_payments_service) { instance_double(GoCardlessPro::Services::PaymentsService) }
  let(:gocardless_mandates_service) { instance_double(GoCardlessPro::Services::MandatesService) }
  let(:gocardless_list_response) { instance_double(GoCardlessPro::ListResponse) }
  let(:code) { "gocardless_1" }

  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "USD",
      invoices: [invoice_1, invoice_2]
    )
  end

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  describe "#create" do
    before do
      gocardless_payment_provider
      gocardless_customer

      allow(GoCardlessPro::Client).to receive(:new)
        .and_return(gocardless_client)
      allow(gocardless_client).to receive(:mandates)
        .and_return(gocardless_mandates_service)
      allow(gocardless_mandates_service).to receive(:list)
        .and_return(gocardless_list_response)
      allow(gocardless_list_response).to receive(:records)
        .and_return([GoCardlessPro::Resources::Mandate.new("id" => "mandate_id")])
      allow(gocardless_client).to receive(:payments)
        .and_return(gocardless_payments_service)
      allow(gocardless_payments_service).to receive(:create)
        .and_return(GoCardlessPro::Resources::Payment.new(
          "id" => "_ID_",
          "amount" => payment_request.total_amount_cents,
          "currency" => payment_request.currency,
          "status" => "paid_out"
        ))
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)
    end

    it "creates a gocardless payment", :aggregate_failures do
      result = gocardless_service.create

      expect(result).to be_success

      expect(result.payable).to be_payment_succeeded
      expect(result.payable.payment_attempts).to eq(1)
      expect(result.payable.reload.ready_for_payment_processing).to eq(false)

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(payment_request)
      expect(result.payment.payment_provider).to eq(gocardless_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(gocardless_customer)
      expect(result.payment.amount_cents).to eq(payment_request.total_amount_cents)
      expect(result.payment.amount_currency).to eq(payment_request.currency)
      expect(result.payment.status).to eq("paid_out")
      expect(gocardless_customer.reload.provider_mandate_id).to eq("mandate_id")

      expect(gocardless_payments_service).to have_received(:create).with(
        {
          headers: {
            "Idempotency-Key" => "#{payment_request.id}/1"
          },
          params:
          {
            amount: 799,
            currency: "USD",
            links: {mandate: "mandate_id"},
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_ids: [invoice_1.id, invoice_2.id],
              lago_payment_request_id: payment_request.id
            },
            retry_if_possible: false
          }
        }
      )
    end

    it "updates invoice payment status to succeeded", :aggregate_failures do
      gocardless_service.create

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_2.reload).to be_payment_succeeded
    end

    context "with no payment provider" do
      let(:gocardless_payment_provider) { nil }

      it "does not creates a gocardless payment", :aggregate_failures do
        result = gocardless_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(gocardless_payments_service).not_to have_received(:create)
      end
    end

    context "with 0 amount" do
      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 0,
          amount_currency: "EUR",
          invoices: [invoice]
        )
      end

      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: 'EUR'
        )
      end

      it "does not creates a gocardless payment", :aggregate_failures do
        result = gocardless_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(result.payable).to be_payment_succeeded
        expect(gocardless_payments_service).not_to have_received(:create)
      end
    end

    context "when customer does not have a provider customer id" do
      before { gocardless_customer.update!(provider_customer_id: nil) }

      it "does not creates a gocardless payment", :aggregate_failures do
        result = gocardless_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(gocardless_payments_service).not_to have_received(:create)
      end
    end

    context "with error on gocardless" do
      before do
        allow(gocardless_payments_service).to receive(:create)
          .and_raise(GoCardlessPro::Error.new("code" => "code", "message" => "error"))
      end

      it "delivers an error webhook" do
        expect { gocardless_service.create }.to raise_error(GoCardlessPro::Error)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: gocardless_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: "code"
            }
          )
      end
    end

    context "when customer has no mandate to make a payment" do
      before do
        allow(gocardless_list_response).to receive(:records)
          .and_return([])

        allow(gocardless_payments_service).to receive(:create)
          .and_raise(GoCardlessPro::Error.new("code" => "code", "message" => "error"))
      end

      it "delivers an error webhook", :aggregate_failures do
        result = gocardless_service.create

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("no_mandate_error")
        expect(result.error.error_message).to eq("No mandate available for payment")
        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.reload.ready_for_payment_processing).to eq(true)

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: gocardless_customer.provider_customer_id,
            provider_error: {
              message: "No mandate available for payment",
              error_code: "no_mandate_error"
            }
          )
      end
    end
  end
end
