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
      expect(invoice_1.ready_for_payment_processing).to eq(false)

      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)
    end

    context "when payment request payment status is already succeeded" do
      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          payment_status: "succeeded",
          amount_cents: 799,
          amount_currency: "EUR"
        )
      end

      it "does not creates a payment", :aggregate_failures do
        result = gocardless_service.create

        expect(result).to be_success
        expect(result.payable).to be_payment_succeeded
        expect(result.payment).to be_nil

        expect(gocardless_payments_service).not_to have_received(:create)
      end
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
        gocardless_service.create

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

      it "returns a service failure" do
        result = gocardless_service.create

        expect(result).not_to be_success
        expect(result.error.code).to eq("code")
        expect(result.payable).to be_payment_failed
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

      it "marks the payment request as payment failed" do
        result = gocardless_service.create

        expect(result).not_to be_success
        expect(result.error.code).to eq("no_mandate_error")
        expect(payment_request.reload).to be_payment_failed
      end
    end
  end

  describe "#update_payment_status" do
    subject(:result) do
      gocardless_service.update_payment_status(provider_payment_id:, status:)
    end

    let(:status) { "paid_out" }

    let(:payment) do
      create(
        :payment,
        payable: payment_request,
        provider_payment_id: provider_payment_id,
        status: "pending_submission"
      )
    end

    let(:provider_payment_id) { "ch_123456" }

    before do
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it "updates the payment, payment_request and invoice payment_status", :aggregate_failures do
      expect(result).to be_success
      expect(result.payment.status).to eq("paid_out")

      expect(result.payable.reload).to be_payment_succeeded
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_1.ready_for_payment_processing).to eq(false)
      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)
    end

    it "does not send payment requested email" do
      expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
    end

    context "when status is failed" do
      let(:status) { "failed" }

      it "updates the payment, payment_request and invoice status", :aggregate_failures do
        expect(result).to be_success
        expect(result.payment.status).to eq(status)

        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.ready_for_payment_processing).to eq(true)

        expect(invoice_1.reload).to be_payment_failed
        expect(invoice_1.ready_for_payment_processing).to eq(true)

        expect(invoice_2.reload).to be_payment_failed
        expect(invoice_2.ready_for_payment_processing).to eq(true)
      end

      it "sends a payment requested email" do
        expect { result }.to have_enqueued_mail(PaymentRequestMailer, :requested)
          .with(params: {payment_request:}, args: [])
      end
    end

    context "when payment is not found" do
      let(:payment) { nil }
      let(:status) { "paid_out" }

      it "returns a not found error", :aggregate_failures do
        expect(result).not_to be_success
        expect(result.payment).to be_nil
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("gocardless_payment_not_found")
      end
    end

    context "when payment_request and invoice is already payment_succeeded" do
      let(:status) { "paid_out" }

      before do
        payment_request.payment_succeeded!
        invoice_1.payment_succeeded!
        invoice_2.payment_succeeded!
      end

      it "does not update the status of invoice, payment_request and payment" do
        expect { result }
          .to not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment_request.reload.payment_status }
          .and not_change { payment.reload.status }

        expect(result).to be_success
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "with invalid status" do
      let(:status) { "invalid-status" }

      it "does not update the payment_status of payment_request, invoice and payment", :aggregate_failures do
        expect { result }
          .to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and change { payment.reload.status }.to(status)
      end

      it "returns an error", :aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payment_status)
        expect(result.error.messages[:payment_status]).to include("value_is_invalid")
      end

      it "does not send payment requested email" do
        expect { result }.not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end
    end

    context "when payment request is not passed to constructor" do
      let(:gocardless_service) { described_class.new(nil) }
      let(:status) { "paid_out" }

      before do
        payment_request
      end

      it "updates the payment and invoice payment_status" do
        expect(result).to be_success
        expect(result.payment.status).to eq(status)

        expect(result.payable).to be_payment_succeeded
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(invoice_1.reload).to be_payment_succeeded
        expect(invoice_1.ready_for_payment_processing).to eq(false)

        expect(invoice_2.reload).to be_payment_succeeded
        expect(invoice_2.ready_for_payment_processing).to eq(false)
      end
    end
  end
end
