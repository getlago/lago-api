# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CreateService do
  subject(:create_service) { described_class.new(invoice:, payment_provider: provider, payment_method_params:) }

  let(:organization) { create(:organization) }
  let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100, invoice_type: :one_off) }
  let(:customer) { create(:customer, organization:, payment_provider: provider, payment_provider_code:) }
  let(:provider) { "stripe" }
  let(:payment_provider_code) { "stripe_1" }
  let(:payment_provider) { create(:stripe_provider, code: payment_provider_code, organization:) }
  let(:provider_customer) { create(:stripe_customer, payment_provider:, customer:) }
  let(:default_payment_method) { create(:payment_method, customer:, is_default: true) }
  let(:payment_method_params) { {} }

  describe "#call" do
    let(:result) do
      PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
        r.payment = instance_double(Payment, payable_payment_status: "processing")
      end
    end

    let(:provider_class) { PaymentProviders::Stripe::Payments::CreateService }
    let(:provider_service) { instance_double(provider_class) }

    shared_examples "a refused payment that runs its follow-up" do
      it "enqueues one payment failure webhook and the fees payment status update" do
        create_service.call

        expect(SendWebhookJob).to have_been_enqueued
          .with("invoice.payment_failure", invoice, any_args).exactly(:once)
        expect(Invoices::UpdateFeesPaymentStatusJob).to have_been_enqueued.with(invoice)
      end

      context "when the invoice is a credit invoice" do
        let(:invoice) { create(:invoice, :credit, :open, customer:, organization:, total_amount_cents: 100) }
        let(:wallet) { create(:wallet, customer:, organization:) }
        let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, source: :manual, status: :pending) }

        before { create(:fee, fee_type: :credit, invoice:, invoiceable: wallet_transaction) }

        it "fails the prepaid credits" do
          create_service.call

          expect(invoice.reload).to be_payment_failed
          expect(Invoices::PrepaidCreditJob).to have_been_enqueued.with(invoice, :failed)
        end
      end

      context "when the invoice is payment-gated" do
        let(:subscription) do
          create(:subscription, :incomplete, :with_activation_rules,
            activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
            customer:, organization:)
        end
        let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100, status: :open) }

        before { create(:invoice_subscription, invoice:, subscription:) }

        it "resolves the payment activation rule as failed" do
          create_service.call

          expect(invoice.reload).to be_payment_failed
          expect(Subscriptions::ActivationRules::Payment::ResolveJob)
            .to have_been_enqueued.with(subscription, invoice, :failed)
        end
      end
    end

    before do
      provider_customer
      default_payment_method

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
      expect(payment.status).to eq("pending")

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

    context "when invoice is subscription_gated (payment-gated)" do
      let(:subscription) do
        create(:subscription, :incomplete, :with_activation_rules,
          activation_rules_config: [{type: "payment", timeout_hours: 48, status: "pending"}],
          customer:, organization:)
      end
      let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100, status: :open) }
      let(:expected_reference) { "#{invoice.billing_entity.name} - Invoice #{invoice.id}" }

      before do
        create(:invoice_subscription, invoice:, subscription:)

        allow(provider_class)
          .to receive(:new)
          .with(
            payment: an_instance_of(Payment),
            reference: expected_reference,
            metadata: {
              lago_invoice_id: invoice.id,
              lago_customer_id: customer.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
              invoice_type: invoice.invoice_type
            }
          ).and_return(provider_service)
      end

      it "uses invoice ID instead of number in the reference" do
        create_service.call

        expect(provider_class).to have_received(:new).with(hash_including(reference: expected_reference))
      end
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

      context "when gocardless refuses the payment with a validation error" do
        before do
          allow(provider_class).to receive(:new).and_call_original
          stub_gocardless_error(:post, "/payments", status: 422, type: "validation_failed")
        end

        it "marks the invoice payment as failed without raising" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payable_payment_status).to eq("failed")
          expect(invoice.reload).to be_payment_failed
          expect(invoice.ready_for_payment_processing).to be(true)
        end

        it_behaves_like "a refused payment that runs its follow-up"
      end

      context "when gocardless refuses the payment with an error to investigate" do
        before do
          allow(provider_class).to receive(:new).and_call_original
          stub_gocardless_error(:post, "/payments", status: 401, type: "invalid_api_usage")
        end

        it "re-raises the provider failure and marks the invoice payment as failed" do
          expect { create_service.call }.to raise_error(BaseService::ServiceFailure)

          expect(invoice.reload).to be_payment_failed
          expect(invoice.ready_for_payment_processing).to be(true)
        end
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

      context "when adyen refuses the payment" do
        before do
          allow(provider_class).to receive(:new).and_call_original
          stub_adyen_checkout("paymentMethods", body: {storedPaymentMethods: []})
        end

        context "with a validation error" do
          before do
            stub_adyen_checkout("payments", status: 422, body: {errorType: "validation", message: "Invalid card number"})
          end

          it "marks the invoice payment as failed without raising" do
            result = create_service.call

            expect(result).to be_success
            expect(result.payment.payable_payment_status).to eq("failed")
            expect(invoice.reload).to be_payment_failed
            expect(invoice.ready_for_payment_processing).to be(true)
          end

          it_behaves_like "a refused payment that runs its follow-up"
        end

        context "with an error to investigate" do
          before { stub_adyen_checkout("payments", status: 403) }

          it "re-raises the provider failure and marks the invoice payment as failed" do
            expect { create_service.call }.to raise_error(BaseService::ServiceFailure)

            expect(invoice.reload).to be_payment_failed
            expect(invoice.ready_for_payment_processing).to be(true)
          end
        end
      end
    end

    context "with subscription invoice" do
      let(:organization) { create(:organization) }
      let(:subscription_payment_method) { create(:payment_method, customer:, is_default: false) }
      let(:plan) { create(:plan, organization:) }
      let(:subscription) do
        create(:subscription, customer:, plan:, organization:, payment_method: subscription_payment_method)
      end
      let(:invoice) do
        create(:invoice, customer:, organization:, total_amount_cents: 100, invoice_type: :subscription)
      end

      before do
        create(:invoice_subscription, invoice:, subscription:)
      end

      context "when payment method is attached to subscription" do
        it "creates payment with subscription payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(subscription_payment_method.id)
        end
      end

      context "when manual payment method is attached to subscription" do
        let(:subscription) do
          create(:subscription, customer:, plan:, organization:, payment_method_type: "manual")
        end

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when payment method is NOT attached to subscription" do
        let(:subscription) do
          create(:subscription, customer:, plan:, organization:, payment_method: nil)
        end

        it "creates payment with customer default payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(default_payment_method.id)
        end
      end

      context "when payment method is not attached to subscription and there is no default payment method" do
        let(:subscription) do
          create(:subscription, customer:, plan:, organization:, payment_method: nil)
        end
        let(:default_payment_method) { nil }

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when no payment method is determined but the provider customer is pending backfill" do
        let(:subscription) do
          create(:subscription, customer:, plan:, organization:, payment_method: nil)
        end
        let(:default_payment_method) { nil }
        let(:provider_customer) do
          create(:stripe_customer, payment_provider:, customer:).tap do |pc|
            pc.update!(settings: pc.settings.merge("payment_method_id" => "pm_legacy"))
          end
        end

        it "creates a payment relying on the provider fallback method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_present
          expect(result.payment.payment_method_id).to be_nil
        end

        context "when the backfilled payment method has since been discarded" do
          before do
            create(
              :payment_method,
              customer:,
              payment_provider_customer: provider_customer,
              provider_method_id: "pm_legacy"
            ).discard!
          end

          it "does not create a payment" do
            result = create_service.call

            expect(result).to be_success
            expect(result.payment).to be_nil
          end
        end
      end
    end

    context "with credit invoice" do
      let(:organization) { create(:organization) }
      let(:wallet) { create(:wallet, customer:, organization:) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, source: :manual) }
      let(:invoice) do
        create(:invoice, :credit, customer:, organization:, total_amount_cents: 100)
      end

      before do
        wallet_transaction
      end

      context "when payment method is attached to wallet transaction" do
        let(:wt_payment_method) { create(:payment_method, customer:, is_default: false) }
        let(:wallet_transaction) do
          create(:wallet_transaction, wallet:, invoice:, source: :manual, payment_method: wt_payment_method)
        end

        it "creates payment with wallet transaction payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(wt_payment_method.id)
        end
      end

      context "when manual payment method is attached to wallet transaction" do
        let(:wallet_transaction) do
          create(:wallet_transaction, wallet:, invoice:, source: :manual, payment_method_type: "manual")
        end

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when payment method is attached to recurring rule" do
        let(:rule_payment_method) { create(:payment_method, customer:, is_default: false) }
        let(:recurring_rule) do
          create(:recurring_transaction_rule, wallet:, payment_method: rule_payment_method)
        end
        let(:wallet_transaction) do
          create(:wallet_transaction, wallet:, invoice:, source: :interval)
        end

        before { recurring_rule }

        it "creates payment with recurring rule payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(rule_payment_method.id)
        end
      end

      context "when manual payment method is attached to recurring rule" do
        let(:recurring_rule) do
          create(:recurring_transaction_rule, wallet:, payment_method_type: "manual")
        end
        let(:wallet_transaction) do
          create(:wallet_transaction, wallet:, invoice:, source: :interval)
        end

        before { recurring_rule }

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when payment method is attached to wallet" do
        let(:wallet_payment_method) { create(:payment_method, customer:, is_default: false) }
        let(:wallet) { create(:wallet, customer:, organization:, payment_method: wallet_payment_method) }

        it "creates payment with wallet payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(wallet_payment_method.id)
        end
      end

      context "when manual payment method is attached to wallet" do
        let(:wallet) { create(:wallet, customer:, organization:, payment_method_type: "manual") }

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when payment method is NOT attached to any wallet related object" do
        it "creates payment with customer default payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(default_payment_method.id)
        end
      end
    end

    context "with one-off invoice" do
      let(:organization) { create(:organization) }
      let(:invoice) do
        create(:invoice, customer:, organization:, total_amount_cents: 100, invoice_type: :one_off)
      end

      context "when manual payment method is passed in params" do
        let(:payment_method_params) { {payment_method_type: "manual"} }

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
        end
      end

      context "when valid payment method is passed in params" do
        let(:one_off_payment_method) { create(:payment_method, customer:, is_default: false) }
        let(:payment_method_params) { {payment_method_id: one_off_payment_method.id} }

        it "creates payment with passed payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(one_off_payment_method.id)
        end
      end

      context "when payment method is NOT passed in params" do
        it "creates payment with customer default payment method" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment.payment_method_id).to eq(default_payment_method.id)
        end
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

    context "when invoice is closed" do
      before { invoice.closed! }

      it "does not create a payment" do
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
          currency: "EUR",
          invoice_type: :one_off
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

    context "when the customer has no payment provider type and the organization has a single provider" do
      subject(:create_service) { described_class.new(invoice:, payment_method_params:) }

      let(:customer) { create(:customer, organization:, payment_provider: nil, payment_provider_code: nil) }

      it "skips the payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(invoice.reload.payment_status).to eq("pending")
        expect(invoice.payment_attempts).to eq(0)
        expect(invoice.payments.count).to eq(0)
        expect(provider_customer.reload.provider_customer_id).to be_present
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when the customer has no payment provider type and the organization has several providers" do
      let(:customer) { create(:customer, organization:, payment_provider: nil, payment_provider_code: nil) }

      before { create(:stripe_provider, code: "stripe_2", organization:) }

      it "skips the payment without failing" do
        result = nil

        expect { result = create_service.call }.not_to have_enqueued_job(SendWebhookJob)

        expect(result).to be_success
        expect(result.invoice).to eq(invoice)
        expect(result.payment).to be_nil
        expect(invoice.reload.payment_status).to eq("pending")
        expect(invoice.payment_attempts).to eq(0)
        expect(invoice.payments.count).to eq(0)
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when the customer has a payment provider type without code and the organization has several providers" do
      let(:payment_provider_code) { nil }
      let(:payment_provider) { create(:stripe_provider, code: "stripe_1", organization:) }

      before { create(:stripe_provider, code: "stripe_2", organization:) }

      it "raises the provider lookup failure without a payment failure webhook" do
        expect { create_service.call }
          .to raise_error(BaseService::ServiceFailure) { |error| expect(error.code).to eq("payment_provider_code_missing") }
          .and not_have_enqueued_job(SendWebhookJob)

        expect(invoice.reload.payment_status).to eq("pending")
        expect(invoice.payment_attempts).to eq(0)
        expect(invoice.payments.count).to eq(0)
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

    context "when the stripe customer only uses customer_balance" do
      let(:default_payment_method) { nil }
      let(:provider_customer) do
        create(:stripe_customer, payment_provider:, customer:, provider_payment_methods: %w[customer_balance])
      end

      it "creates a payment so an awaiting-funds payment intent is opened" do
        result = create_service.call

        expect(result).to be_success
        expect(result.payment).to be_present
        expect(result.payment.payment_method_id).to be_nil
        expect(provider_class).to have_received(:new)
      end

      context "when the customer only uses crypto" do
        let(:provider_customer) do
          create(:stripe_customer, payment_provider:, customer:, provider_payment_methods: %w[crypto])
        end

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
          expect(provider_class).not_to have_received(:new)
        end
      end

      context "when the customer also uses a payment method requiring setup" do
        let(:provider_customer) do
          create(:stripe_customer, payment_provider:, customer:, provider_payment_methods: %w[card crypto])
        end

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
          expect(provider_class).not_to have_received(:new)
        end
      end

      context "when the customer has no provider payment methods" do
        before { provider_customer.update_column(:settings, {}) } # rubocop:disable Rails/SkipsModelValidations

        it "does not create a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
          expect(provider_class).not_to have_received(:new)
        end
      end
    end

    context "when a non-stripe provider customer has no payment method" do
      let(:provider) { "adyen" }
      let(:provider_class) { PaymentProviders::Adyen::Payments::CreateService }
      let(:payment_provider) { create(:adyen_provider, code: payment_provider_code, organization:) }
      let(:provider_customer) { create(:adyen_customer, payment_provider:, customer:) }
      let(:default_payment_method) { nil }

      it "does not create a payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.payment).to be_nil
        expect(provider_class).not_to have_received(:new)
      end
    end

    context "when the provider updates the payment during the charge" do
      let(:provider_payment_status) { "succeeded" }
      let(:result) do
        PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
          r.payment = instance_double(Payment, payable_payment_status: provider_payment_status)
        end
      end

      before do
        provider_payment = nil

        allow(provider_class).to receive(:new) do |payment:, **|
          provider_payment = payment
          provider_service
        end

        # NOTE: The provider service writes the resolved status back onto the payment it was given.
        allow(provider_service).to receive(:call!) do
          provider_payment.update!(payable_payment_status: provider_payment_status)
          result
        end
      end

      it_behaves_like "syncs payment" do
        let(:service_call) { create_service.call }
      end

      context "when the payment is left processing" do
        let(:provider_payment_status) { "processing" }
        let(:integration) { create(:netsuite_integration, organization:, sync_payments: true) }
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }

        before { integration_customer }

        it "does not enqueue Integrations::Aggregator::Payments::CreateJob" do
          expect { create_service.call }.not_to have_enqueued_job(Integrations::Aggregator::Payments::CreateJob)
        end
      end
    end

    context "when the provider raises AlreadyPaidError" do
      before do
        allow(provider_service).to receive(:call!).and_raise(Invoices::Payments::AlreadyPaidError)
      end

      it "skips silently and drops the unused pending payment" do
        result = create_service.call

        expect(result).to be_success
        expect(result.payment).to be_nil
        expect(invoice.reload.payments).to be_empty
      end

      it "does not deliver an error webhook" do
        expect { create_service.call }.not_to have_enqueued_job(SendWebhookJob)
      end
    end

    context "when a concurrent attempt already advanced the shared payment (regression)" do
      it "does not destroy a payment that now has a provider reference" do
        # A parallel attempt operates on the same pending row (only one pending/processing
        # provider payment exists per payable). It sets a real provider reference just before
        # this attempt finds the invoice already paid.
        allow(provider_service).to receive(:call!) do
          invoice.reload.payments.first.update!(provider_payment_id: "pi_concurrent")
          raise Invoices::Payments::AlreadyPaidError
        end

        result = create_service.call

        expect(result).to be_success
        expect(result.payment).to be_nil

        payment = invoice.reload.payments.first
        expect(payment).to be_present
        expect(payment.provider_payment_id).to eq("pi_concurrent")
      end

      it "does not destroy a payment that was already marked succeeded" do
        allow(provider_service).to receive(:call!) do
          invoice.reload.payments.first.update!(payable_payment_status: "succeeded")
          raise Invoices::Payments::AlreadyPaidError
        end

        result = create_service.call

        expect(result).to be_success
        expect(invoice.reload.payments.first).to be_present
      end
    end

    context "when provider service raises a service failure" do
      let(:original_error) { ::Stripe::StripeError.new("card declined") }
      let(:result) do
        PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
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
          PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
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
        let(:wallet) { create(:wallet, customer:, organization:) }
        let(:wallet_transaction) { create(:wallet_transaction, wallet:, invoice:, source: :manual) }
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

      Customer::PAYMENT_PROVIDERS.filter_map { PaymentProviders::CreatePaymentFactory.service_class(provider: it) }.each do |refusing_service|
        context "when #{refusing_service.module_parent.module_parent.name.demodulize} refuses the payment" do
          let(:result) do
            refusing_service::Result.new.tap do |r|
              r.payment = instance_double(Payment, status: "failed", payable_payment_status: "failed")
              r.error_message = "error"
              r.error_code = "code"
              r.reraise = reraise
            end
          end

          context "when the refusal is re-raised" do
            let(:reraise) { true }

            it "re-raises the provider failure and marks the invoice payment as failed" do
              expect { create_service.call }.to raise_error(BaseService::ServiceFailure)

              expect(invoice.reload).to be_payment_failed
            end
          end

          context "when the refusal is not re-raised" do
            let(:reraise) { false }

            it "marks the invoice payment as failed without raising" do
              expect(create_service.call).to be_success

              expect(invoice.reload).to be_payment_failed
            end
          end
        end
      end

      context "when payable_payment_status is pending" do
        let(:result) do
          PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
            r.payment = instance_double(Payment, status: "failed", payable_payment_status: "pending")
            r.error_message = "stripe_error"
            r.error_code = "unknown"
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

      [
        ::PaymentProviders::StripeProvider::AMOUNT_TOO_SMALL_ERROR_CODE,
        ::PaymentProviders::StripeProvider::NEED_3DS_ERROR_CODE
      ].each do |error_code|
        context "when error_code is is pending" do
          let(:result) do
            PaymentProviders::Stripe::Payments::CreateService::Result.new.tap do |r|
              r.payment = instance_double(Payment, status: "failed", payable_payment_status: "failed")
              r.error_message = "stripe_error"
              r.error_code = error_code
            end
          end

          it "updates the invoice payment status and does not delivers an error webhook" do
            expect(invoice.payment_status).to eq "pending"

            result = create_service.call

            expect(provider_class).to have_received(:new)
            expect(provider_service).to have_received(:call!)
            expect(result.invoice.payment_status).to eq "failed"

            expect(SendWebhookJob).not_to have_been_enqueued
          end
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

      context "when the provider customer of the pending payment was discarded" do
        let(:current_provider_customer) { create(:stripe_customer, payment_provider:, customer:) }

        before do
          provider_customer.discard!
          current_provider_customer
        end

        it "sends the payment to the provider with the current provider customer" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to eq(payment)

          expect(payment.reload.payment_provider_id).to eq(payment_provider.id)
          expect(payment.payment_provider_customer_id).to eq(current_provider_customer.id)
          expect(payment.payment_provider_customer).to eq(current_provider_customer)
          expect(payment.amount_cents).to eq(invoice.total_due_amount_cents)

          expect(provider_class).to have_received(:new)
            .with(hash_including(payment: having_attributes(payment_provider_customer_id: current_provider_customer.id)))
          expect(provider_service).to have_received(:call!)
        end

        context "when the invoice was partially paid after the pending payment was stored" do
          let(:invoice) do
            create(:invoice, customer:, organization:, invoice_type: :one_off, total_amount_cents: 10_000, total_paid_amount_cents: 3_000)
          end

          it "charges the due amount of the invoice to the current provider customer" do
            create_service.call

            # total 10_000 - paid 3_000 - offset 0
            expect(payment.reload.amount_cents).to eq(10_000 - 3_000)
            expect(provider_class).to have_received(:new)
              .with(hash_including(payment: having_attributes(amount_cents: 7_000, payment_provider_customer_id: current_provider_customer.id)))
          end
        end
      end

      context "when the reused pending payment has a provider status" do
        before { payment.update!(status: "requires_payment_method") }

        it "keeps the provider status of the payment" do
          create_service.call

          expect(payment.reload.status).to eq("requires_payment_method")
          expect(payment.payable_payment_status).to eq("pending")
        end
      end

      context "when the stored payment method of the pending payment is outdated" do
        let(:old_payment_method) { create(:payment_method, customer:, is_default: false) }

        before { payment.update!(payment_method_id: old_payment_method.id) }

        it "charges the payment with the current default payment method" do
          create_service.call

          expect(payment.reload.payment_method_id).to eq(default_payment_method.id)
        end

        context "when a payment method is passed in params" do
          let(:other_payment_method) { create(:payment_method, customer:, is_default: false) }
          let(:payment_method_params) { {payment_method_id: other_payment_method.id} }

          it "charges the payment with the passed payment method" do
            create_service.call

            expect(payment.reload.payment_method_id).to eq(other_payment_method.id)
          end
        end
      end

      context "when the customer moved to another payment provider" do
        subject(:create_service) { described_class.new(invoice:, payment_provider: :stripe, payment_method_params:) }

        let(:customer) { create(:customer, organization:, payment_provider: "gocardless", payment_provider_code: "gocardless_1") }
        let(:gocardless_provider) { create(:gocardless_provider, code: "gocardless_1", organization:) }
        let(:gocardless_customer) { create(:gocardless_customer, payment_provider: gocardless_provider, customer:) }
        let(:gocardless_class) { PaymentProviders::Gocardless::Payments::CreateService }

        before do
          gocardless_customer

          allow(gocardless_class).to receive(:new).and_return(provider_service)
        end

        it "charges the reused payment through the current provider" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to eq(payment)

          expect(payment.reload.payment_provider_id).to eq(gocardless_provider.id)
          expect(payment.payment_provider_customer_id).to eq(gocardless_customer.id)

          expect(gocardless_class).to have_received(:new)
            .with(hash_including(payment: having_attributes(payment_provider_customer_id: gocardless_customer.id)))
          expect(provider_class).not_to have_received(:new)
          expect(provider_service).to have_received(:call!)
        end
      end

      context "when the invoice was partially paid after the pending payment was stored" do
        let(:invoice) do
          create(:invoice, customer:, organization:, invoice_type: :one_off, total_amount_cents: 10_000, total_paid_amount_cents: 3_000)
        end

        it "keeps the stored amount sent under the same idempotency key" do
          create_service.call

          expect(payment.reload.amount_cents).to eq(10_000)
          expect(provider_class).to have_received(:new)
            .with(hash_including(payment: having_attributes(amount_cents: 10_000)))
        end
      end

      context "when a credit note offset the invoice after the pending payment was stored" do
        let(:invoice) { create(:invoice, customer:, organization:, invoice_type: :one_off, total_amount_cents: 10_000) }

        before { create(:credit_note, invoice:, customer:, organization:, status: :finalized, offset_amount_cents: 2_500) }

        it "keeps the stored amount sent under the same idempotency key" do
          create_service.call

          expect(payment.reload.amount_cents).to eq(10_000)
        end
      end

      context "when the customer no longer has a provider customer id" do
        before { provider_customer.update!(provider_customer_id: nil) }

        it "skips the payment and leaves the pending payment untouched" do
          result = create_service.call

          expect(result).to be_success
          expect(result.payment).to be_nil
          expect(payment.reload.payment_provider_customer_id).to eq(provider_customer.id)
          expect(provider_class).not_to have_received(:new)
        end
      end

      context "when payment is already processing" do
        let(:payment_status) { "processing" }

        it "does not creates a payment" do
          result = create_service.call

          expect(result).to be_success
          expect(result.invoice).to eq(invoice)
          expect(result.payment).to eq(payment)

          expect(payment.reload.payment_provider_customer_id).to eq(provider_customer.id)
          expect(payment.amount_cents).to eq(invoice.total_amount_cents)
          expect(invoice.payments.count).to eq(1)

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
        .with(invoice:, payment_provider: :stripe, payment_method_params: {})
    end

    context "with gocardless payment provider" do
      let(:provider) { "gocardless" }

      it "enqueues a job to create a gocardless payment" do
        expect { create_service.call_async }
          .to have_enqueued_job_after_commit(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :gocardless, payment_method_params: {})
      end
    end

    context "with adyen payment provider" do
      let(:provider) { "adyen" }

      it "enqueues a job to create a gocardless payment" do
        expect { create_service.call_async }
          .to have_enqueued_job_after_commit(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :adyen, payment_method_params: {})
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

    context "when the organization has used a checkout URL" do
      before { create(:payment_intent, invoice: create(:invoice, customer:, organization:)) }

      it "delays the first auto-payment" do
        freeze_time do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(described_class::CHECKOUT_AUTO_PAYMENT_DELAY.from_now)
        end
      end

      context "when the organization skips the credit invoice auto-payment delay" do
        before { organization.enable_feature_flag!(:skip_credit_invoice_auto_payment_delay) }

        it "enqueues the payment of a one-off invoice immediately" do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(:no_wait)
        end

        context "when the invoice is a subscription invoice" do
          let(:invoice) { create(:invoice, customer:, organization:, total_amount_cents: 100, invoice_type: :subscription) }

          it "still delays the first auto-payment" do
            freeze_time do
              expect { ApplicationRecord.transaction { create_service.call_async } }
                .to have_enqueued_job(Invoices::Payments::CreateJob)
                .with(invoice:, payment_provider: :stripe, payment_method_params: {})
                .at(described_class::CHECKOUT_AUTO_PAYMENT_DELAY.from_now)
            end
          end
        end
      end

      context "when it is not the first payment attempt (retry)" do
        before { invoice.update!(payment_attempts: 1) }

        it "enqueues the payment immediately" do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(:no_wait)
        end
      end

      context "when the invoice gates a payment-gated subscription" do
        let(:invoice) do
          create(:invoice, customer:, organization:, total_amount_cents: 100, invoice_type: :subscription)
        end

        before { allow(invoice).to receive(:subscription_payment_gated?).and_return(true) }

        it "enqueues the payment immediately" do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(:no_wait)
        end
      end

      context "when the invoice is an automatic (interval/threshold) wallet top-up" do
        let(:invoice) { create(:invoice, :credit, customer:, organization:, total_amount_cents: 100) }

        before do
          wallet = create(:wallet, customer:, organization:)
          create(:wallet_transaction, wallet:, invoice:, source: :interval)
        end

        it "enqueues the payment immediately" do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(:no_wait)
        end
      end

      context "when the invoice is a manual wallet top-up" do
        let(:invoice) { create(:invoice, :credit, customer:, organization:, total_amount_cents: 100) }

        before do
          wallet = create(:wallet, customer:, organization:)
          create(:wallet_transaction, wallet:, invoice:, source: :manual)
        end

        it "delays the first auto-payment" do
          freeze_time do
            expect { ApplicationRecord.transaction { create_service.call_async } }
              .to have_enqueued_job(Invoices::Payments::CreateJob)
              .with(invoice:, payment_provider: :stripe, payment_method_params: {})
              .at(described_class::CHECKOUT_AUTO_PAYMENT_DELAY.from_now)
          end
        end

        context "when the organization skips the credit invoice auto-payment delay" do
          before { organization.enable_feature_flag!(:skip_credit_invoice_auto_payment_delay) }

          it "enqueues the payment immediately" do
            expect { ApplicationRecord.transaction { create_service.call_async } }
              .to have_enqueued_job(Invoices::Payments::CreateJob)
              .with(invoice:, payment_provider: :stripe, payment_method_params: {})
              .at(:no_wait)
          end
        end
      end
    end

    context "when another customer of the same organization has used a checkout URL" do
      before do
        other_customer = create(:customer, organization:)
        create(:payment_intent, invoice: create(:invoice, customer: other_customer, organization:))
      end

      it "still delays the first auto-payment (covers the customer's first invoice)" do
        freeze_time do
          expect { ApplicationRecord.transaction { create_service.call_async } }
            .to have_enqueued_job(Invoices::Payments::CreateJob)
            .with(invoice:, payment_provider: :stripe, payment_method_params: {})
            .at(described_class::CHECKOUT_AUTO_PAYMENT_DELAY.from_now)
        end
      end
    end

    context "when the organization has never used a checkout URL" do
      it "enqueues the payment immediately" do
        expect { ApplicationRecord.transaction { create_service.call_async } }
          .to have_enqueued_job(Invoices::Payments::CreateJob)
          .with(invoice:, payment_provider: :stripe, payment_method_params: {})
          .at(:no_wait)
      end
    end
  end
end
