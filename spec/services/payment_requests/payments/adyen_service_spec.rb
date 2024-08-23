# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::AdyenService, type: :service do
  subject(:adyen_service) { described_class.new(payment_request) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:adyen_payment_provider) { create(:adyen_provider, organization:, code:) }
  let(:adyen_customer) { create(:adyen_customer, customer:) }
  let(:adyen_client) { instance_double(Adyen::Client) }
  let(:payments_api) { Adyen::PaymentsApi.new(adyen_client, 70) }
  let(:checkout) { Adyen::Checkout.new(adyen_client, 70) }
  let(:payments_response) { generate(:adyen_payments_response) }
  let(:payment_methods_response) { generate(:adyen_payment_methods_response) }
  let(:code) { "adyen_1" }

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
      adyen_payment_provider
      adyen_customer

      allow(Adyen::Client).to receive(:new)
        .and_return(adyen_client)
      allow(adyen_client).to receive(:checkout)
        .and_return(checkout)
      allow(checkout).to receive(:payments_api)
        .and_return(payments_api)
      allow(payments_api).to receive(:payments)
        .and_return(payments_response)
      allow(payments_api).to receive(:payment_methods)
        .and_return(payment_methods_response)
    end

    it "creates an adyen payment", :aggregate_failures do
      result = adyen_service.create

      expect(result).to be_success

      expect(result.payable).to be_payment_succeeded
      expect(result.payable.payment_attempts).to eq(1)
      expect(result.payable.reload.ready_for_payment_processing).to eq(false)

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(payment_request)
      expect(result.payment.payment_provider).to eq(adyen_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(adyen_customer)
      expect(result.payment.amount_cents).to eq(payment_request.total_amount_cents)
      expect(result.payment.amount_currency).to eq(payment_request.currency)
      expect(result.payment.status).to eq("Authorised")

      expect(adyen_customer.reload.payment_method_id)
        .to eq(payment_methods_response.response["storedPaymentMethods"].first["id"])

      expect(payments_api).to have_received(:payments)

      # TODO: add expection of the payload send to Adyen with the right data,
      #      for example the list of invoice ids within its metadata...
      #      does ayden params has metadata?
    end

    xit "updates invoice payment status to succeeded", :aggregate_failures do
      adyen_service.create

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_2.reload).to be_payment_succeeded
    end

    context "with no payment provider" do
      let(:adyen_payment_provider) { nil }

      it "does not creates a adyen payment", :aggregate_failures do
        result = adyen_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(payments_api).not_to have_received(:payments)
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

      it "does not creates a adyen payment", :aggregate_failures do
        result = adyen_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(result.payable).to be_payment_succeeded
        expect(payments_api).not_to have_received(:payments)
      end
    end

    context "when customer does not have a provider customer id" do
      before { adyen_customer.update!(provider_customer_id: nil) }

      it "does not creates a adyen payment", :aggregate_failures do
        result = adyen_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(payments_api).not_to have_received(:payments)
      end
    end

    context "with error response from adyen" do
      let(:payments_error_response) { generate(:adyen_payments_error_response) }

      before do
        allow(payments_api).to receive(:payments).and_return(payments_error_response)
      end

      it "delivers an error webhook" do
        expect { adyen_service.create }.to enqueue_job(SendWebhookJob)
          .with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: adyen_customer.provider_customer_id,
            provider_error: {
              message: "There are no payment methods available for the given parameters.",
              error_code: "validation"
            }
          ).on_queue(:webhook)
      end
    end

    context "with validation error on adyen" do
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      context "when changing payment method fails with invalid card" do
        before do
          allow(payments_api).to receive(:payment_methods)
            .and_raise(Adyen::ValidationError.new("Invalid card number", nil))
        end

        it "delivers an error webhook" do
          expect { adyen_service.create }.to enqueue_job(SendWebhookJob)
            .with(
              "payment_request.payment_failure",
              payment_request,
              provider_customer_id: adyen_customer.provider_customer_id,
              provider_error: {
                message: "Invalid card number",
                error_code: nil
              }
            ).on_queue(:webhook)
        end
      end

      context "when payment fails with invalid card" do
        before do
          allow(payments_api).to receive(:payments)
            .and_raise(Adyen::ValidationError.new("Invalid card number", nil))
        end

        it "delivers an error webhook" do
          expect { adyen_service.create }.to enqueue_job(SendWebhookJob)
            .with(
              "payment_request.payment_failure",
              payment_request,
              provider_customer_id: adyen_customer.provider_customer_id,
              provider_error: {
                message: "Invalid card number",
                error_code: nil
              }
            ).on_queue(:webhook)
        end
      end
    end

    context "with error on adyen" do
      let(:customer) do
        create(:customer, organization:, payment_provider_code: code)
      end

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      before do
        allow(payments_api).to receive(:payments)
          .and_raise(Adyen::AdyenError.new(nil, nil, "error", "code"))
      end

      it "delivers an error webhook" do
        expect { adyen_service.create }.to raise_error(Adyen::AdyenError)
          .and enqueue_job(SendWebhookJob).with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: adyen_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: "code"
            }
          )
      end
    end
  end

  # PRIVATE METHOD, DOH!!!!!
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
end
