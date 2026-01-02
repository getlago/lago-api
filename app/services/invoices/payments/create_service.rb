# frozen_string_literal: true

module Invoices
  module Payments
    class CreateService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(invoice:, payment_provider: nil, payment_method_params: {})
        @invoice = invoice
        @provider = payment_provider&.to_sym
        @payment_method_params = payment_method_params

        super
      end

      def call
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        if processing_payment
          # Payment is being processed, return the existing payment
          # Status will be updated via webhooks
          result.payment = processing_payment
          return result
        end

        invoice.update!(payment_attempts: invoice.payment_attempts + 1)

        payment ||= Payment.create_with(
          organization_id: invoice.organization_id,
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: invoice.total_due_amount_cents,
          amount_currency: invoice.currency,
          status: "pending",
          customer_id: invoice.customer_id
        ).find_or_create_by!(
          payable: invoice,
          payable_payment_status: "pending"
        )

        if multiple_payment_methods_enabled?
          payment.payment_method_id = determine_payment_method&.id
          payment.save!
        end

        result.payment = payment

        payment_result = ::PaymentProviders::CreatePaymentFactory.new_instance(
          provider:,
          payment:,
          reference: "#{invoice.billing_entity.name} - Invoice #{invoice.number}",
          metadata: {
            lago_invoice_id: invoice.id,
            lago_customer_id: invoice.customer_id,
            invoice_issuing_date: invoice.issuing_date.iso8601,
            invoice_type: invoice.invoice_type
          }
        ).call!

        payment_status = payment_result.payment.payable_payment_status
        update_invoice_payment_status(payment_status:)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if result.payment.should_sync_payment?

        result
      rescue BaseService::ServiceFailure => e
        result.payment = e.result.payment

        deliver_error_webhook(e) unless skip_error_webhook?(e)

        update_invoice_payment_status(payment_status: e.result.payment.payable_payment_status)

        raise RetriableError if e.result.should_retry

        # Some errors should be investigated and need to be raised
        raise if e.result.reraise

        result
      end

      def call_async
        return result unless provider

        Invoices::Payments::CreateJob.perform_after_commit(invoice:, payment_provider: provider, payment_method_params:)

        result.payment_provider = provider
        result
      end

      private

      attr_reader :invoice, :payment, :payment_method_params

      delegate :customer, to: :invoice

      def provider
        @provider ||= invoice.customer.payment_provider&.to_sym
      end

      # TODO: Replace with real feature flag once implemented
      def multiple_payment_methods_enabled?
        customer.organization.premium_integrations.include?("manual_payments")
      end

      def should_process_payment?
        return false if invoice.self_billed?
        return false if invoice.payment_succeeded? || invoice.voided?
        return false if current_payment_provider.blank?

        if multiple_payment_methods_enabled?
          determine_payment_method.present?
        else
          current_payment_provider_customer&.provider_customer_id
        end
      end

      def current_payment_provider
        @current_payment_provider ||= payment_provider(customer)
      end

      def current_payment_provider_customer
        @current_payment_provider_customer ||= customer.payment_provider_customers
          .find_by(payment_provider_id: current_payment_provider.id)
      end

      def update_invoice_payment_status(payment_status:)
        params = {
          # NOTE: A proper `processing` payment status should be introduced for invoices
          payment_status: (payment_status.to_s == "processing") ? :pending : payment_status,
          ready_for_payment_processing: %w[pending failed].include?(payment_status.to_s)
        }

        if payment_status.to_s == "succeeded"
          total_paid_amount_cents = invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
          params[:total_paid_amount_cents] = total_paid_amount_cents
        end

        Invoices::UpdateService.call!(
          invoice:,
          params:,
          webhook_notification: payment_status.to_sym == :succeeded
        )
      end

      def skip_error_webhook?(e)
        return true if e.result.payment.payable_payment_status&.to_sym == :pending

        [
          ::PaymentProviders::StripeProvider::AMOUNT_TOO_SMALL_ERROR_CODE,
          ::PaymentProviders::StripeProvider::NEED_3DS_ERROR_CODE
        ].include?(e.result.error_code)
      end

      def deliver_error_webhook(e)
        payment_result = e.result

        DeliverErrorWebhookService.call_async(invoice, {
          provider_customer_id: current_payment_provider_customer.provider_customer_id,
          provider_error: {
            message: payment_result.error_message,
            error_code: payment_result.error_code
          },
          error_details: e.original_error ? V1::Errors::ErrorSerializerFactory.new_instance(e.original_error).serialize : {}
        })
      end

      def processing_payment
        @processing_payment ||= Payment.find_by(
          payable: invoice,
          payment_provider_id: current_payment_provider.id,
          payment_provider_customer_id: current_payment_provider_customer.id,
          amount_cents: invoice.total_amount_cents,
          amount_currency: invoice.currency,
          payable_payment_status: "processing"
        )
      end

      # NOTE: Returns PaymentMethod object or nil
      #       nil means: skip automatic payment (manual type or no payment method configured)
      #       payment_method_params takes precedence (used for retry with override)
      def determine_payment_method
        @determine_payment_method ||= if payment_method_params.present?
          determine_override_payment_method
        else
          determine_invoice_payment_method
        end
      end

      def determine_override_payment_method
        return nil if payment_method_params[:payment_method_type] == "manual"

        if payment_method_params[:payment_method_id].present?
          customer.payment_methods.find_by(id: payment_method_params[:payment_method_id])
        else
          customer.default_payment_method
        end
      end

      def determine_invoice_payment_method
        case invoice.invoice_type
        when "subscription", "advance_charges", "progressive_billing"
          determine_subscription_payment_method
        when "credit"
          determine_credit_payment_method
        else
          customer.default_payment_method
        end
      end

      def determine_subscription_payment_method
        subscription = invoice.invoice_subscriptions.first&.subscription
        return nil unless subscription

        return nil if subscription.payment_method_type == "manual"

        if subscription.payment_method_id.present?
          return customer.payment_methods.find_by(id: subscription.payment_method_id)
        end

        customer.default_payment_method
      end

      def determine_credit_payment_method
        wallet_transaction = invoice.wallet_transactions.first
        return nil unless wallet_transaction

        return nil if wallet_transaction.payment_method_type == "manual"

        if wallet_transaction.payment_method_id.present?
          return customer.payment_methods.find_by(id: wallet_transaction.payment_method_id)
        end

        if wallet_transaction.source.to_s.in?(%w[interval threshold])
          rule = wallet_transaction.wallet.recurring_transaction_rules.active.first
          return nil if rule&.payment_method_type == "manual"
          return customer.payment_methods.find_by(id: rule.payment_method_id) if rule&.payment_method_id.present?
        end

        wallet = wallet_transaction.wallet
        return nil if wallet.payment_method_type == "manual"

        if wallet.payment_method_id.present?
          return customer.payment_methods.find_by(id: wallet.payment_method_id)
        end

        customer.default_payment_method
      end
    end
  end
end
