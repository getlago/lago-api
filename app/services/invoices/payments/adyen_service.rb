# frozen_string_literal: true

module Invoices
  module Payments
    class AdyenService < BaseService
      PENDING_STATUSES = %w[Authorised AuthorisedPending Received]
        .freeze
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
          amount_cents: adyen_result.amount,
          amount_currency: adyen_result.currency&.upcase,
          provider_payment_id: adyen_result.id,
          status: adyen_result.status,
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
        )
      end

      def adyen_payment_provider
        @adyen_payment_provider ||= organization.adyen_payment_provider
      end

      def mandate_id
        result = client.mandates.list(
          params: {
            customer: customer.adyen_customer.provider_customer_id,
            status: %w[pending_customer_approval pending_submission submitted active],
          },
        )

        mandate = result&.records&.first

        customer.adyen_customer.provider_mandate_id = mandate&.id
        customer.adyen_customer.save!

        mandate&.id
      end

      def create_adyen_payment
        client.payments.create(
          params: {
            amount: invoice.total_amount_cents,
            currency: invoice.currency.upcase,
            retry_if_possible: false,
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
            },
            links: {
              mandate: mandate_id,
            },
          },
          headers: {
            'Idempotency-Key' => "#{invoice.id}/#{invoice.payment_attempts}",
          },
        )
      rescue Adyen::AdyenError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)

        raise
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
