# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::CreateService do
  subject(:create_service) { described_class.new(payment:, reference:, metadata:) }

  let(:customer) { create(:customer, payment_provider_code: code, country:) }
  let(:country) { "CA" }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_method_id: "pm_123456", payment_provider: stripe_payment_provider) }
  let(:code) { "stripe_1" }
  let(:reference) { "organization.name - Invoice #{invoice.number}" }
  let(:currency) { "EUR" }
  let(:metadata) do
    {
      lago_customer_id: customer.id,
      lago_invoice_id: invoice.id,
      lago_payment_id: payment.id,
      invoice_issuing_date: invoice.issuing_date.iso8601,
      invoice_type: invoice.invoice_type,
      lago_payable_id: payment.payable_id,
      lago_payable_type: payment.payable_type,
      lago_organization_id: payment.payable.organization_id,
      lago_billing_entity_id: payment.payable.billing_entity.id
    }
  end

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency:,
      ready_for_payment_processing: true
    )
  end

  let(:payment) do
    create(
      :payment,
      payable: invoice,
      status: "pending",
      payment_provider: stripe_payment_provider,
      payment_provider_customer: stripe_customer,
      amount_cents: invoice.total_amount_cents,
      amount_currency: invoice.currency
    )
  end

  describe ".call" do
    let(:provider_customer_service_result) do
      BaseService::Result.new.tap do |result|
        result.payment_method = Stripe::PaymentMethod.new(id: "pm_123456")
      end
    end

    let(:customer_response) do
      get_stripe_fixtures("customer_retrieve_response.json")
    end

    let(:stripe_payment_intent_data) do
      {
        id: "pi_123456",
        status: payment_status,
        amount: invoice.total_amount_cents,
        currency: invoice.currency
      }
    end

    let(:payment_status) { "succeeded" }

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create).and_call_original
      stub_request(:post, "https://api.stripe.com/v1/payment_intents")
        .to_return(body: stripe_payment_intent_data.to_json)

      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)

      allow(PaymentProviderCustomers::Stripe::CheckPaymentMethodService).to receive(:call)
        .and_return(provider_customer_service_result)

      stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
        .to_return(status: 200, body: customer_response, headers: {})
    end

    it "creates a stripe payment and a payment" do
      result = create_service.call

      expect(result).to be_success

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(invoice)
      expect(result.payment.payment_provider).to eq(stripe_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(stripe_customer)
      expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
      expect(result.payment.amount_currency).to eq(invoice.currency)
      expect(result.payment.status).to eq("succeeded")
      expect(result.payment.payable_payment_status).to eq("succeeded")

      expect(Stripe::PaymentIntent).to have_received(:create)
    end

    context "when customer does not have a payment method" do
      let(:stripe_customer) { create(:stripe_customer, customer:, payment_provider: stripe_payment_provider) }

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .and_return(Stripe::StripeObject.construct_from(
            {
              invoice_settings: {
                default_payment_method: nil
              },
              default_source: nil
            }
          ))

        allow(Stripe::Customer).to receive(:list_payment_methods).and_call_original
        stub_request(:get, %r{/v1/customers/#{stripe_customer.provider_customer_id}/payment_methods}).and_return(
          status: 200, body: get_stripe_fixtures("customer_list_payment_methods_response.json") do |h|
            h[:data][0][:id] = "pm_123456"
          end
        )
      end

      it "retrieves the payment method" do
        result = create_service.call

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq(stripe_customer.provider_customer_id)
        expect(customer.stripe_customer.payment_method_id).to eq("pm_123456")

        expect(Stripe::Customer).to have_received(:list_payment_methods).with(stripe_customer.provider_customer_id, {}, anything)
        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context "with card error on stripe" do
      let(:payment_response) do
        get_stripe_fixtures("payment_intent_card_declined_response.json") do |h|
          h["error"]["payment_intent"]["id"] = "pi_declined"
        end
      end

      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:subscription) do
        create(:subscription, organization:, customer:)
      end

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      before do
        subscription

        stub_request(:post, "https://api.stripe.com/v1/payment_intents")
          .to_return(status: 402, body: payment_response, headers: {})
      end

      it "returns a failed result" do
        result = create_service.call

        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stripe_error")
        expect(result.error.error_message).to eq("Your card was declined.")

        expect(result.error_message).to eq("Your card was declined.")
        expect(result.error_code).to eq("card_declined")
        expect(result.payment.status).to eq("failed")
        expect(result.payment.payable_payment_status).to eq("failed")
        expect(payment.reload.provider_payment_id).to eq("pi_declined")
      end
    end

    context "with stripe error" do
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:subscription) do
        create(:subscription, organization:, customer:)
      end

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      before do
        subscription

        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(::Stripe::StripeError.new("error"))
      end

      it "returns a success result with error messages" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stripe_error")
        expect(result.error.error_message).to eq("error")

        expect(result.error_message).to eq("error")
        expect(result.error_code).to be_nil

        expect(result.payment.status).to eq("failed")
        expect(result.payment.payable_payment_status).to eq("failed")
      end
    end

    context "when invoice has a too small amount" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:) }

      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 20,
          currency: "EUR",
          ready_for_payment_processing: true
        )
      end

      before do
        subscription

        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(::Stripe::InvalidRequestError.new("amount_too_small", {}, code: "amount_too_small"))
      end

      it "returns an empty result" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stripe_error")
        expect(result.error.error_message).to eq("amount_too_small")

        expect(result.error_message).to eq("amount_too_small")
        expect(result.error_code).to eq("amount_too_small")
        expect(result.payment.status).to eq("failed")
        expect(result.payment.payable_payment_status).to eq("pending")
      end
    end

    context "when invoice amount is too big to pay with Boleto" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, organization:, customer:) }

      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 100_000_00,
          currency: "BRL",
          ready_for_payment_processing: true
        )
      end

      before do
        subscription

        WebMock.stub_request(:post, "https://api.stripe.com/v1/payment_intents")
          .to_return(status: 400, body: {
            error: {
              code: "amount_too_large",
              doc_url: "https://stripe.com/docs/error-codes/amount-too-large",
              message: "Amount must be no more than R$ 49,999.99 brl",
              param: "amount",
              request_log_url: "https://dashboard.stripe.com/test/logs/req_WAmkqXs7ajMNAU?t=1738144303",
              type: "invalid_request_error"
            }
          }.to_json)
      end

      it "returns an empty result" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("stripe_error")
        expect(result.error.error_message).to eq("Amount must be no more than R$ 49,999.99 brl")

        expect(result.error_message).to eq("Amount must be no more than R$ 49,999.99 brl")
        expect(result.error_code).to eq("amount_too_large")
        expect(result.payment.status).to eq("failed")
        expect(result.payment.payable_payment_status).to eq("failed")
      end
    end

    context "when payment status is processing" do
      let(:payment_status) { "processing" }

      it "creates a stripe payment and a payment" do
        result = create_service.call

        expect(result).to be_success

        expect(result.payment.id).to be_present
        expect(result.payment.payable).to eq(invoice)
        expect(result.payment.payment_provider).to eq(stripe_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(stripe_customer)
        expect(result.payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(result.payment.amount_currency).to eq(invoice.currency)
        expect(result.payment.status).to eq("processing")
        expect(result.payment.payable_payment_status).to eq("processing")

        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context "when payment requires action" do
      let(:payment_status) { "requires_action" }

      let(:stripe_payment_intent_data) do
        {
          id: "pi_123456",
          status: payment_status,
          amount: invoice.total_amount_cents,
          currency: invoice.currency,
          next_action: {
            redirect_to_url: {url: "https://foo.bar"}
          }
        }
      end

      it "creates a stripe payment and payment with requires_action status" do
        result = create_service.call

        expect(result).to be_success
        expect(result.payment.status).to eq("requires_action")
        expect(result.payment.provider_payment_data).not_to be_empty
      end

      it "has enqueued a SendWebhookJob" do
        result = create_service.call

        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "payment.requires_action",
            result.payment
          )
      end
    end

    describe "#payment_intent_payload" do
      let(:payment_intent_payload) { create_service.__send__(:payment_intent_payload) }
      let(:payload) do
        {
          amount: invoice.total_amount_cents,
          currency: invoice.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: customer.stripe_customer.payment_method_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          return_url: create_service.__send__(:success_redirect_url),
          description: reference,
          metadata: metadata
        }
      end

      it "returns the payload" do
        expect(payment_intent_payload).to eq(payload)
      end

      context "when using customer balance as a payment method" do
        let(:stripe_customer) {
          create(:stripe_customer, customer:, payment_method_id: "pm_123456", payment_provider: stripe_payment_provider, provider_payment_methods: ["customer_balance"])
        }

        let(:base_payload) do
          payload.merge(
            payment_method_data: {type: "customer_balance"},
            payment_method_options: {
              customer_balance: {
                funding_type: "bank_transfer"
              }
            }
          ).tap { |p| p.delete(:payment_method) }
        end

        context "when currency is EUR" do
          let(:currency) { "EUR" }
          let(:country) { "DE" }

          it "includes EU bank transfer details" do
            expected_payload = base_payload.deep_merge(
              payment_method_options: {
                customer_balance: {
                  bank_transfer: {
                    eu_bank_transfer: {country:},
                    type: "eu_bank_transfer"
                  }
                }
              }
            )

            expect(payment_intent_payload).to eq(expected_payload)
          end
        end

        context "when currency is USD" do
          let(:currency) { "USD" }

          it "includes US bank transfer details" do
            expected_payload = base_payload.deep_merge(
              payment_method_options: {
                customer_balance: {
                  bank_transfer: {type: "us_bank_transfer"}
                }
              }
            )
            expect(payment_intent_payload).to eq(expected_payload)
          end
        end

        context "when currency is GBP" do
          let(:currency) { "GBP" }

          it "includes GBP bank transfer details" do
            expected_payload = base_payload.deep_merge(
              payment_method_options: {
                customer_balance: {
                  bank_transfer: {type: "gb_bank_transfer"}
                }
              }
            )
            expect(payment_intent_payload).to eq(expected_payload)
          end
        end
      end
    end
  end
end
