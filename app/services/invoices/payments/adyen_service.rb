# frozen_string_literal: true

module Invoices
  module Payments
    class AdyenService < BaseService
      PENDING_STATUSES = %w[Authorised AuthorisedPending Received].freeze
      SUCCESS_STATUSES = %w[SentForSettle SettleScheduled Settled Refunded].freeze
      FAILED_STATUSES = %w[Cancelled CaptureFailed Error Expired Refused].freeze

      def initialize(invoice = nil)
        @invoice = invoice

        super(nil)
      end

      def create
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        increment_payment_attempts

        adyen_result = create_adyen_payment

        payment = Payment.new(
          invoice:,
          payment_provider_id: adyen_payment_provider.id,
          payment_provider_customer_id: customer.adyen_customer.id,
          amount_cents: adyen_result.dig("amount", "value"),
          amount_currency: adyen_result.dig("amount", "currency"),
          provider_payment_id: adyen_result["pspReference"],
          status: adyen_result["resultCode"],
        )
        payment.save!

        invoice_payment_status = invoice_payment_status(payment.status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        result.payment = payment
        result
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: 'adyen_payment') unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status:)

        invoice_payment_status = invoice_payment_status(status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false if invoice.succeeded?
        return false if adyen_payment_provider.blank?

        customer&.adyen_customer&.provider_customer_id
      end

      def client
        @client ||= Adyen::Client.new(
          api_key: adyen_payment_provider.api_key,
          env: adyen_payment_provider.environment,
          live_url_prefix: adyen_payment_provider.live_prefix 
        )
      end

      def adyen_payment_provider
        @adyen_payment_provider ||= organization.adyen_payment_provider
      end

      def create_adyen_payment
        client.checkout.payments_api.payments(payment_params)
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)

        raise
      end

      def payment_params
        {
          amount: {
            currency: invoice.currency.upcase,
            value: invoice.total_amount_cents
          },
          reference: invoice.id,
          paymentMethod: {
            type: "scheme",
            storedPaymentMethodId: invoice.customer.adyen_customer.payment_method_id
          },
          shopperReference: invoice.customer.external_id,
          merchantAccount: invoice.customer.adyen_customer.merchant_account,
          shopperInteraction: "ContAuth",
          recurringProcessingModel: "UnscheduledCardOnFile"
        }
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true)
        result = Invoices::UpdateService.call(
          invoice:,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded,
          },
          webhook_notification: deliver_webhook,
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(adyen_error)
        return unless invoice.organization.webhook_url?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.adyen_customer.provider_customer_id,
          provider_error: {
            message: adyen_error.msg,
            error_code: adyen_error.code,
          },
        )
      end
    end
  end
end
