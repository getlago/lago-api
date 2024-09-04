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

      expect(payments_api)
        .to have_received(:payments)
        .with(
          {
            amount: {
              currency: "USD",
              value: 799
            },
            applicationInfo: {
              externalPlatform: {integrator: "Lago", name: "Lago"},
              merchantApplication: {name: "Lago"}
            },
            merchantAccount: adyen_payment_provider.merchant_account,
            paymentMethod: {
              storedPaymentMethodId: adyen_customer.payment_method_id,
              type: "scheme"
            },
            recurringProcessingModel: "UnscheduledCardOnFile",
            reference: "Overdue invoices",
            shopperEmail: customer.email,
            shopperInteraction: "ContAuth",
            shopperReference: adyen_customer.provider_customer_id
          }
        )
    end

    it "updates invoice payment status to succeeded", :aggregate_failures do
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

  describe "#generate_payment_url" do
    let(:payment_links_api) { Adyen::PaymentLinksApi.new(adyen_client, 70) }
    let(:payment_links_response) { generate(:adyen_payment_links_response) }

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
      freeze_time do
        adyen_service.generate_payment_url

        expect(payment_links_api)
          .to have_received(:payment_links)
          .with(
            {
              amount: {
                currency: "USD",
                value: 799
              },
              applicationInfo: {
                externalPlatform: {integrator: "Lago", name: "Lago"},
                merchantApplication: {name: "Lago"}
              },
              expiresAt: Time.current + 70.days,
              merchantAccount: adyen_payment_provider.merchant_account,
              metadata: {
                lago_customer_id: customer.id,
                lago_payment_request_id: payment_request.id,
                payment_type: "one-time"
              },
              recurringProcessingModel: "UnscheduledCardOnFile",
              reference: "Overdue invoices",
              returnUrl: adyen_payment_provider.success_redirect_url,
              shopperEmail: customer.email,
              shopperReference: customer.external_id,
              storePaymentMethodMode: "enabled"
            }
          )
      end
    end

    context "when payment request is payment_succeeded" do
      before { payment_request.payment_succeeded! }

      it "does not generate payment url" do
        adyen_service.generate_payment_url

        expect(payment_links_api).not_to have_received(:payment_links)
      end
    end
  end

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

  describe "#update_payment_status" do
    let(:payment) do
      create(
        :payment,
        payable: payment_request,
        provider_payment_id:,
        status: "Pending"
      )
    end

    let(:provider_payment_id) { "ch_123456" }

    before do
      allow(SendWebhookJob).to receive(:perform_later)
      allow(SegmentTrackJob).to receive(:perform_later)
      payment
    end

    it "updates the payment, payment_request and invoices payment_status", :aggregate_failures do
      result = adyen_service.update_payment_status(
        provider_payment_id:,
        status: "Authorised"
      )

      expect(result).to be_success
      expect(result.payment.status).to eq("Authorised")

      expect(result.payable.reload).to be_payment_succeeded
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_1.ready_for_payment_processing).to eq(false)
      expect(invoice_2.reload).to be_payment_succeeded
      expect(invoice_2.ready_for_payment_processing).to eq(false)
    end

    context "when status is failed" do
      it "updates the payment, payment_request and invoices status", :aggregate_failures do
        result = adyen_service.update_payment_status(
          provider_payment_id:,
          status: "Refused"
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("Refused")

        expect(result.payable.reload).to be_payment_failed
        expect(result.payable.ready_for_payment_processing).to eq(true)

        expect(invoice_1.reload).to be_payment_failed
        expect(invoice_1.ready_for_payment_processing).to eq(true)

        expect(invoice_2.reload).to be_payment_failed
        expect(invoice_2.ready_for_payment_processing).to eq(true)
      end
    end

    context "when payment_request and invoices is already payment_succeeded" do
      before do
        payment_request.payment_succeeded!
        invoice_1.payment_succeeded!
        invoice_2.payment_succeeded!
      end

      it "does not update the status of invoices, payment_request and payment" do
        expect {
          adyen_service.update_payment_status(
            provider_payment_id:,
            status: %w[Authorised SentForSettle SettleScheduled Settled Refunded].sample
          )
        }.to not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and not_change { payment_request.reload.payment_status }
          .and not_change { payment.reload.status }

        result = adyen_service.update_payment_status(
          provider_payment_id:,
          status: %w[Authorised SentForSettle SettleScheduled Settled Refunded].sample
        )

        expect(result).to be_success
      end
    end

    context "with invalid status" do
      let(:status) { "invalid-status" }

      it "does not update the payment_status of payment_request, invoices and payment" do
        expect {
          adyen_service.update_payment_status(provider_payment_id:, status:)
        }.to not_change { payment_request.reload.payment_status }
          .and not_change { invoice_1.reload.payment_status }
          .and not_change { invoice_2.reload.payment_status }
          .and change { payment.reload.status }.to(status)
      end

      it "returns an error", :aggregate_failures do
        result = adyen_service.update_payment_status(provider_payment_id:, status:)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages.keys).to include(:payment_status)
        expect(result.error.messages[:payment_status]).to include("value_is_invalid")
      end
    end

    context "when payment is not found and it is one time payment" do
      let(:payment) { nil }

      before do
        adyen_payment_provider
        adyen_customer
      end

      it "creates a payment and updates payment request and invoices payment status", :aggregate_failures do
        result = adyen_service.update_payment_status(
          provider_payment_id:,
          status: "succeeded",
          metadata: {
            lago_payment_request_id: payment_request.id,
            payment_type: "one-time"
          }
        )

        expect(result).to be_success
        expect(result.payment.status).to eq("succeeded")

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
