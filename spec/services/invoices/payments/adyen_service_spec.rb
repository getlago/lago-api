# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(invoice) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:adyen_payment_provider) { create(:adyen_provider, organization:, code:) }
  let(:adyen_customer) { create(:adyen_customer, customer:, payment_provider: adyen_payment_provider) }
  let(:adyen_client) { instance_double(Adyen::Client) }
  let(:payments_api) { Adyen::PaymentsApi.new(adyen_client, 70) }
  let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }
  let(:payment_links_response) { generate(:adyen_payment_links_response) }
  let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
  let(:payments_response) { generate(:adyen_payments_response) }
  let(:payment_methods_response) { generate(:adyen_payment_methods_response) }
  let(:code) { "adyen_1" }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 1000,
      total_paid_amount_cents:,
      currency: "USD",
      ready_for_payment_processing: true
    )
  end

  let(:total_paid_amount_cents) { 0 }

  describe "#payment_method_params" do
    subject(:payment_method_params) { adyen_service.__send__(:payment_method_params) }

    let(:params) do
      {
        merchantAccount: adyen_payment_provider.merchant_account,
        shopperReference: adyen_customer.provider_customer_id
      }
    end

    before do
      adyen_payment_provider
      adyen_customer
    end

    it "returns payment method params" do
      expect(payment_method_params).to eq(params)
    end
  end

  describe ".update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: invoice,
        provider_payment_id: "ch_123456",
        status: "Pending",
        payment_provider: adyen_payment_provider
      )
    end

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      payment
    end

    it "updates the payment and invoice payment_status" do
      result = adyen_service.update_payment_status(
        provider_payment_id: "ch_123456",
        status: "Authorised"
      )

      expect(result).to be_success
      expect(result.payment.status).to eq("Authorised")
      expect(result.payment.payable_payment_status).to eq("succeeded")
      expect(result.invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: 200
      )
    end

    context "when status is failed" do
      it "updates the payment and invoice status" do
        result = adyen_service.update_payment_status(
          provider_payment_id: "ch_123456",
          status: "Refused"
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("Refused")
        expect(result.payment.payable_payment_status).to eq("failed")
        expect(result.invoice.reload).to have_attributes(
          payment_status: "failed",
          ready_for_payment_processing: true
        )
      end
    end

    context "when invoice is already payment_succeeded" do
      before { invoice.payment_succeeded! }

      it "does not update the status of invoice and payment" do
        result = adyen_service.update_payment_status(
          provider_payment_id: "ch_123456",
          status: %w[Authorised SentForSettle SettleScheduled Settled Refunded].sample
        )

        expect(result).to be_success
        expect(result.invoice.payment_status).to eq("succeeded")
      end
    end

    context "with invalid status" do
      it "does not update the payment_status of invoice" do
        result = adyen_service.update_payment_status(
          provider_payment_id: "ch_123456",
          status: "foo-bar"
        )

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:payable_payment_status)
          expect(result.error.messages[:payable_payment_status]).to include("value_is_invalid")
        end
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }

      before do
        adyen_payment_provider
        adyen_customer
      end

      it "creates a payment and updates invoice payment status" do
        result = adyen_service.update_payment_status(
          provider_payment_id: "ch_123456",
          status: "succeeded",
          metadata: {lago_invoice_id: invoice.id, payment_type: "one-time"}
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.payment.status).to eq("succeeded")
          expect(result.payment.payable_payment_status).to eq("succeeded")
          expect(result.invoice.reload).to have_attributes(
            payment_status: "succeeded",
            ready_for_payment_processing: false
          )
        end
      end
    end
  end

  describe "#payment_url_params" do
    subject(:payment_url_params) { adyen_service.__send__(:payment_url_params) }

    let(:expected_params) do
      {
        reference: invoice.number,
        amount: {
          value: invoice.total_due_amount_cents,
          currency: invoice.currency.upcase
        },
        merchantAccount: adyen_payment_provider.merchant_account,
        returnUrl: adyen_service.__send__(:success_redirect_url),
        shopperReference: customer.external_id,
        storePaymentMethodMode: "enabled",
        recurringProcessingModel: "UnscheduledCardOnFile",
        expiresAt: (Time.current + 1.day),
        metadata: {
          lago_customer_id: customer.id,
          lago_invoice_id: invoice.id,
          invoice_issuing_date: invoice.issuing_date.iso8601,
          invoice_type: invoice.invoice_type,
          payment_type: "one-time"
        },
        shopperEmail: customer.email
      }
    end

    before do
      adyen_payment_provider
      adyen_customer
    end

    context "when paid amount is not zero" do
      let(:total_paid_amount_cents) { 1 }

      it "return the payload" do
        freeze_time do
          expect(payment_url_params).to eq(expected_params)
        end
      end
    end

    context "when paid amount is zero" do
      it "returns the payload" do
        freeze_time do
          expect(payment_url_params).to eq(expected_params)
        end
      end
    end

    context "when customer has an email" do
      let(:customer) { create(:customer, payment_provider_code: code, email: "test@example.com") }

      it "includes the shopperEmail in the params" do
        expect(payment_url_params[:shopperEmail]).to eq("test@example.com")
      end
    end

    context "when customer does not have an email" do
      let(:customer) { create(:customer, payment_provider_code: code, email: nil) }

      it "does not include the shopperEmail in the params" do
        expect(payment_url_params).not_to have_key(:shopperEmail)
      end
    end
  end

  describe "#generate_payment_url" do
    before do
      adyen_payment_provider
      adyen_customer

      allow(Adyen::Client).to receive(:new)
        .and_return(adyen_client)
      allow(adyen_client).to receive(:checkout)
        .and_return(checkout)
      allow(checkout).to receive(:payment_links_api)
        .and_return(payment_links_api)
      allow(payment_links_api).to receive(:payment_links)
        .and_return(payment_links_response)
    end

    it "generates payment url" do
      adyen_service.generate_payment_url

      expect(payment_links_api).to have_received(:payment_links)
    end

    context "with an error on Adyen" do
      before do
        allow(payment_links_api).to receive(:payment_links)
          .and_raise(Adyen::AdyenError.new(nil, nil, "error"))
      end

      it "returns a failed result" do
        result = adyen_service.generate_payment_url

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq("Adyen")
        expect(result.error.error_message).to eq("error")
      end
    end
  end
end
