# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(payment:) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) { create(:stripe_customer, customer:, payment_method_id: "pm_123456", payment_provider: stripe_payment_provider) }
  let(:code) { "stripe_1" }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: "EUR",
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
    let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }

    let(:provider_customer_service_result) do
      BaseService::Result.new.tap do |result|
        result.payment_method = Stripe::PaymentMethod.new(id: "pm_123456")
      end
    end

    let(:customer_response) do
      File.read(Rails.root.join("spec/fixtures/stripe/customer_retrieve_response.json"))
    end

    let(:stripe_payment_intent) do
      Stripe::PaymentIntent.construct_from(
        id: "ch_123456",
        status: payment_status,
        amount: invoice.total_amount_cents,
        currency: invoice.currency
      )
    end

    let(:payment_status) { "succeeded" }

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(stripe_payment_intent)
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(Invoices::PrepaidCreditJob).to receive(:perform_later)

      allow(PaymentProviderCustomers::StripeService).to receive(:new)
        .and_return(provider_customer_service)
      allow(provider_customer_service).to receive(:check_payment_method)
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

      expect(result.payment_status).to eq(:succeeded)

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

        allow(Stripe::PaymentMethod).to receive(:list)
          .and_return(Stripe::ListObject.construct_from(
            data: [
              {
                id: "pm_123456",
                object: "payment_method",
                card: {brand: "visa"},
                created: 1_656_422_973,
                customer: "cus_123456",
                livemode: false,
                metadata: {},
                type: "card"
              }
            ]
          ))
      end

      it "retrieves the payment method" do
        result = create_service.call

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq(stripe_customer.provider_customer_id)
        expect(customer.stripe_customer.payment_method_id).to eq("pm_123456")

        expect(Stripe::PaymentMethod).to have_received(:list)
        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context "with card error on stripe" do
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
          .and_raise(::Stripe::CardError.new("error", {}))
      end

      it "returns a success result with error messages" do
        result = create_service.call

        expect(result).to be_success
        expect(result.error_message).to eq("error")
        expect(result.error_code).to be_nil
        expect(result.payment_status).to eq(:failed)
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

        expect(result).to be_success
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

        expect(result.payment_status).to eq(:pending)

        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context "when customers country is IN" do
      let(:payment_status) { "requires_action" }

      let(:stripe_payment_intent) do
        Stripe::PaymentIntent.construct_from(
          id: "ch_123456",
          status: payment_status,
          amount: invoice.total_amount_cents,
          currency: invoice.currency,
          next_action: {
            redirect_to_url: {url: "https://foo.bar"}
          }
        )
      end

      before do
        customer.update(country: "IN")
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
            result.payment,
            provider_customer_id: stripe_customer.provider_customer_id
          )
      end
    end

    context "with #payment_intent_payload" do
      let(:payment_intent_payload) { create_service.__send__(:payment_intent_payload) }
      let(:payload) do
        {
          amount: invoice.total_amount_cents,
          currency: invoice.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: customer.stripe_customer.payment_method_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          off_session: true,
          return_url: create_service.__send__(:success_redirect_url),
          error_on_requires_action: true,
          description: create_service.__send__(:description),
          metadata: {
            lago_customer_id: customer.id,
            lago_invoice_id: invoice.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        }
      end

      it "returns the payload" do
        expect(payment_intent_payload).to eq(payload)
      end

      context "when customers country is IN" do
        before do
          payload[:off_session] = false
          payload[:error_on_requires_action] = false
          customer.update!(country: "IN")
        end

        it "returns the payload" do
          expect(payment_intent_payload).to eq(payload)
        end
      end
    end

    context "with #description" do
      let(:description_call) { create_service.__send__(:description) }
      let(:description) { "#{organization.name} - Invoice #{invoice.number}" }

      it "returns the description" do
        expect(description_call).to eq(description)
      end
    end
  end
end
