# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::AdyenService do
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

    it "enqueues a SendWebhookJob for payment.succeeded" do
      expect do
        adyen_service.update_payment_status(
          provider_payment_id: "ch_123456",
          status: "Authorised"
        )
      end.to have_enqueued_job(SendWebhookJob).with("payment.succeeded", Payment)
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

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payable_payment_status)
        expect(result.error.messages[:payable_payment_status]).to include("value_is_invalid")
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

  describe "#payment_url_params" do
    subject(:payment_url_params) { adyen_service.send(:payment_url_params, payment_intent) }

    let(:payment_intent) { create(:payment_intent) }

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
        expiresAt: payment_intent.expires_at.iso8601,
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
    let(:payment_intent) { create(:payment_intent) }

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
      adyen_service.generate_payment_url(payment_intent)

      expect(payment_links_api).to have_received(:payment_links)
    end

    it "exposes the provider session id" do
      result = adyen_service.generate_payment_url(payment_intent)

      expect(result.provider_session_id).to eq(payment_links_response.response["id"])
    end

    context "with an error on Adyen" do
      before do
        allow(payment_links_api).to receive(:payment_links)
          .and_raise(Adyen::AdyenError.new(nil, nil, "error"))
      end

      it "returns a failed result" do
        result = adyen_service.generate_payment_url(payment_intent)

        expect(result).not_to be_success

        expect(result.error).to be_a(BaseService::ThirdPartyFailure)
        expect(result.error.third_party).to eq("Adyen")
        expect(result.error.error_message).to eq("error")
      end
    end
  end

  describe "#checkout_session_already_completed?" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: "PL123") }
    let(:get_response) { OpenStruct.new(response: {"status" => link_status}) }
    let(:link_status) { "active" }

    before do
      adyen_payment_provider
      adyen_customer
      allow(Adyen::Client).to receive(:new).and_return(adyen_client)
      allow(adyen_client).to receive(:checkout).and_return(checkout)
      allow(checkout).to receive(:payment_links_api).and_return(payment_links_api)
      allow(payment_links_api).to receive(:get_payment_link).and_return(get_response)
    end

    it "returns false for active links" do
      expect(adyen_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    %w[completed paymentPending].each do |status|
      context "when status is #{status}" do
        let(:link_status) { status }

        it "returns true" do
          expect(adyen_service.checkout_session_already_completed?(payment_intent)).to be true
        end
      end
    end

    it "returns false when provider_session_id is missing" do
      payment_intent.update!(provider_session_id: nil)
      expect(adyen_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    it "swallows Adyen errors and returns false" do
      allow(payment_links_api).to receive(:get_payment_link).and_raise(Adyen::AdyenError.new(nil, nil, "boom"))
      expect(adyen_service.checkout_session_already_completed?(payment_intent)).to be false
    end

    it "swallows connection failures so auto-charge isn't blocked" do
      allow(payment_links_api).to receive(:get_payment_link).and_raise(Faraday::ConnectionFailed.new("timeout"))
      expect(adyen_service.checkout_session_already_completed?(payment_intent)).to be false
    end
  end

  describe "#expire_checkout_session" do
    let(:payment_intent) { create(:payment_intent, invoice:, provider_session_id: "PL123") }

    before do
      adyen_payment_provider
      adyen_customer
      allow(Adyen::Client).to receive(:new).and_return(adyen_client)
      allow(adyen_client).to receive(:checkout).and_return(checkout)
      allow(checkout).to receive(:payment_links_api).and_return(payment_links_api)
      allow(payment_links_api).to receive(:update_payment_link).and_return(OpenStruct.new(response: {}))
    end

    it "patches the link to expired" do
      adyen_service.expire_checkout_session(payment_intent)

      expect(payment_links_api).to have_received(:update_payment_link).with({status: "expired"}, "PL123")
    end

    it "does nothing when provider_session_id is missing" do
      payment_intent.update!(provider_session_id: nil)
      adyen_service.expire_checkout_session(payment_intent)

      expect(payment_links_api).not_to have_received(:update_payment_link)
    end

    it "lets Adyen errors bubble up unwrapped (job will surface them)" do
      allow(payment_links_api).to receive(:update_payment_link).and_raise(Adyen::AdyenError.new(nil, nil, "boom"))
      expect { adyen_service.expire_checkout_session(payment_intent) }
        .to raise_error(Adyen::AdyenError)
    end

    it "wraps Faraday connection failures as Invoices::Payments::ConnectionError" do
      allow(payment_links_api).to receive(:update_payment_link)
        .and_raise(Faraday::ConnectionFailed.new("timeout"))
      expect { adyen_service.expire_checkout_session(payment_intent) }
        .to raise_error(Invoices::Payments::ConnectionError)
    end

    it "wraps Adyen 429 errors as Invoices::Payments::RateLimitError" do
      allow(payment_links_api).to receive(:update_payment_link)
        .and_raise(Adyen::AdyenError.new(nil, nil, "rate limited", 429))
      expect { adyen_service.expire_checkout_session(payment_intent) }
        .to raise_error(Invoices::Payments::RateLimitError)
    end
  end
end
