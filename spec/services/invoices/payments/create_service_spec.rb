# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CreateService do
  subject(:create_service) { described_class.new(invoice:, payment_provider: provider) }

  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100) }
  let(:customer) { create(:customer, organization:, payment_provider: provider, payment_provider_code:) }
  let(:provider) { "stripe" }
  let(:payment_provider_code) { "stripe_1" }
  let(:payment_provider) { create(:stripe_provider, code: payment_provider_code, organization:) }
  let(:provider_customer) { create(:stripe_customer, payment_provider:, customer:) }

  describe "#call" do
    let(:result) do
      BaseService::Result.new.tap do |r|
        r.payment = instance_double(Payment, payable_payment_status: "processing")
      end
    end

    let(:provider_class) { PaymentProviders::Stripe::Payments::CreateService }
    let(:provider_service) { instance_double(provider_class) }

    before do
      provider_customer

      allow(provider_class)
        .to receive(:new)
        .with(
          payment: an_instance_of(Payment),
          reference: "#{invoice.billing_entity.name} - Invoice #{invoice.number}",
          metadata: {
            lago_invoice_id: invoice.id,
            lago_customer_id: customer.id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        ).and_return(provider_service)
      allow(provider_service).to receive(:call!)
        .and_return(result)
    end

    it "creates a payment and calls the stripe service" do
      result = create_service.call

      expect(result).to be_success
      expect(result.invoice).to eq(invoice)
      expect(result.payment).to be_present

      payment = result.payment
      expect(payment.payment_provider).to eq(payment_provider)
      expect(payment.payment_provider_customer).to eq(provider_customer)
      expect(payment.amount_cents).to eq(invoice.total_amount_cents)
      expect(payment.amount_currency).to eq(invoice.currency)
      expect(payment.payable).to eq(invoice)

      expect(provider_class).to have_received(:new)
      expect(provider_service).to have_received(:call!)
    end

    it "updates the invoice payment status" do
      create_service.call

      expect(invoice.reload).to be_payment_pending
      expect(invoice.payment_attempts).to eq(1)
      expect(invoice.ready_for_payment_processing).to be_falsey
      expect(invoice.payments.count).to eq(1)
    end

    context "with gocardless payment provider" do
      let(:provider) { "gocardless" }
      let(:provider_class) { PaymentProviders::Gocardless::Payments::CreateService }
      let(:payment_provider) { create(:gocardless_provider, code: payment_provider_code, organization:) }
      let(:provider_customer) { create(:gocardless_customer, payment_provider:, customer:) }

      it "calls the gocardless service" do
        create_service.call

        expect(provider_class).to have_received(:new)
        expect(provider_service).to have_received(:call!)
      end
    end

    context "with adyen payment provider" do
      let(:provider) { "adyen" }
      let(:provider_class) { PaymentProviders::Adyen::Payments::CreateService }
      let(:payment_provider) { create(:adyen_provider, code: payment_provider_code, organization:) }
      let(:provider_customer) { create(:adyen_customer, payment_provider:, customer:) }

      it "calls the adyen service" do
        create_service.call

        expect(provider_class).to have_received(:new)
        expect(provider_service).to have_received(:call!)
      end
    end

    context "when invoice is self_billed" do
      let(:invoice) do
        create(:invoice, :self_billed, customer:, organization:, total_amount_cents: 100)
      end

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when invoice is payment_succeeded" do
      before { invoice.payment_succeeded! }

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when invoice is voided" do
      before { invoice.voided! }

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when invoice amount is 0" do
      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: "EUR"
        )
      end

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(result.invoice).to be_payment_succeeded
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "with missing payment provider" do
      let(:payment_provider) { nil }

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when customer does not have a provider customer id" do
      before { provider_customer.update!(provider_customer_id: nil) }

      it "does not creates a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    it_behaves_like "syncs payment" do
      let(:service_call) { create_service.call }
    end

    context "when provider service raises a service failure" do
      let(:original_error) { ::Stripe::StripeError.new("card declined") }
      let(:result) do
        BaseService::Result.new.tap do |r|
          r.payment = instance_double(Payment, status: "failed", payable_payment_status: "failed")
          r.error_message = "error"
          r.error_code = "code"
          r.reraise = true
        end
      end

      before do
        allow(provider_service).to receive(:call!)
          .and_raise(BaseService::ServiceFailure.new(result, code: "code", error_message: "error", original_error:))
      end

      it "re-raise the error and delivers an error webhook" do
        expect { create_service.call }
          .to raise_error(BaseService::ServiceFailure)
          .and enqueue_job(SendWebhookJob)
          .with(
            "invoice.payment_failure",
            invoice,
            provider_customer_id: provider_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: "code"
            },
            error_details: Hash
          ).on_queue(webhook_queue)
      end

      context "when original_error is not set" do
        let(:original_error) { nil }

        it "re-raise the error and delivers an error webhook" do
          expect { create_service.call }
            .to raise_error(BaseService::ServiceFailure)
            .and enqueue_job(SendWebhookJob)
            .with(
              "invoice.payment_failure",
              invoice,
              provider_customer_id: provider_customer.provider_customer_id,
              provider_error: {
                message: "error",
                error_code: "code"
              },
              error_details: {}
            ).on_queue(webhook_queue)
        end
      end

      context "when payment has a payable_payment_status" do
        let(:result) do
          BaseService::Result.new.tap do |r|
            r.payment = instance_double(Payment, payable_payment_status: "failed")
            r.error_message = "error"
            r.error_code = "code"
            r.reraise = true
          end
        end

        it "updates the invoice payment status" do
          expect { create_service.call }
            .to raise_error(BaseService::ServiceFailure)

          expect(invoice.reload).to be_payment_failed
        end
      end

      context "when invoice is credit? and open?" do
        let(:invoice) { create(:invoice, :credit, :open, customer:, organization:, total_amount_cents: 100) }
        let(:wallet_transaction) { create(:wallet_transaction) }
        let(:fee) { create(:fee, fee_type: :credit, invoice: invoice, invoiceable: wallet_transaction) }

        before do
          fee

          allow(Invoices::Payments::DeliverErrorWebhookService)
            .to receive(:call_async).and_call_original
        end

        it "delivers an error webhook" do
          expect { create_service.call }.to raise_error(BaseService::ServiceFailure)

          expect(Invoices::Payments::DeliverErrorWebhookService).to have_received(:call_async)
          expect(SendWebhookJob).to have_been_enqueued
            .with(
              "wallet_transaction.payment_failure",
              wallet_transaction,
              provider_customer_id: provider_customer.provider_customer_id,
              provider_error: {
                message: "error",
                error_code: "code"
              },
              error_details: Hash
            )
        end
      end

      context "when payable_payment_status is pending" do
        let(:result) do
          BaseService::Result.new.tap do |r|
            r.payment = instance_double(Payment, status: "failed", payable_payment_status: "pending")
            r.error_message = "stripe_error"
            r.error_code = "amount_too_small"
          end
        end

        it "updates the invoice payment status and does not delivers an error webhook" do
          result = create_service.call

          expect(result).to be_success
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to be_present

          expect(result.payment.status).to eq("failed")
          expect(result.payment.payable_payment_status).to eq("pending")

          expect(provider_class).to have_received(:new)
          expect(provider_service).to have_received(:call!)

          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end
    end

    context "when a payment exists" do
      let(:payment) do
        create(
          :payment,
          payable: invoice,
          payment_provider:,
          payment_provider_customer: provider_customer,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency,
          status: "pending",
          payable_payment_status: payment_status
        )
      end

      let(:payment_status) { "pending" }

      before { payment }

      it "retrieves the payment for processing" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to eq(payment)

        expect(payment.payment_provider).to eq(payment_provider)
        expect(payment.payment_provider_customer).to eq(provider_customer)
        expect(payment.amount_cents).to eq(invoice.total_amount_cents)
        expect(payment.amount_currency).to eq(invoice.currency)
        expect(payment.payable).to eq(invoice)

        expect(provider_class).to have_received(:new)
        expect(provider_service).to have_received(:call!)
      end

      context "when payment is already processing" do
        let(:payment_status) { "processing" }

        it "does not creates a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to eq(payment)

          expect(provider_class).not_to have_received(:new)
          expect(provider_service).not_to have_received(:call!)
        end
      end
    end
  end

  describe "#call_async" do
    it "enqueues a job to create a stripe payment" do
      expect {
        result = create_service.call_async
        expect(result).to be_success
        expect(result.payment_provider).to eq(provider.to_sym)
      }.to have_enqueued_job_after_commit(Invoices::Payments::CreateJob)
        .with(invoice:, payment_provider: :stripe)
    end

    context "with gocardless payment provider" do
      let(:provider) { "gocardless" }

      it "enqueues a job to create a gocardless payment" do
        expect { create_service.call_async }
          .to have_enqueued_job_after_commit(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :gocardless)
      end
    end

    context "with adyen payment provider" do
      let(:provider) { "adyen" }

      it "enqueues a job to create a gocardless payment" do
        expect { create_service.call_async }
          .to have_enqueued_job_after_commit(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :adyen)
      end
    end

    context "when payment provider is not set" do
      let(:provider) { nil }

      it "does not enqueue a job" do
        expect {
          result = create_service.call_async
          expect(result).to be_success
          expect(result.payment_provider).to be_nil
        }.not_to have_enqueued_job(Invoices::Payments::CreateJob)
      end
    end
  end
end
