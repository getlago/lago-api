# frozen_string_literal: true

module Invoices
  module Payments
    class PinetService < BaseService
      PENDING_STATUSES = %w[processing]
        .freeze
      SUCCESS_STATUSES = %w[succeeded].freeze
      FAILED_STATUSES = %w[canceled].freeze

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

        pinet_result = create_pinet_payment
        # NOTE: return if payment was not processed
        return result unless pinet_result
        payment = Payment.new(
          invoice:,
          payment_provider_id: organization.pinet_payment_provider.id,
          payment_provider_customer_id: customer.pinet_customer.id,
          amount_cents: pinet_result.amount,
          amount_currency: pinet_result.currency&.upcase,
          provider_payment_id: pinet_result.id,
          status: pinet_result.status,
        )
        payment.save!

        update_invoice_payment_status(
          payment_status: invoice_payment_status(payment.status),
          processing: payment.status == 'processing',
        )

        result.payment = payment
        result
      end

      def update_payment_status(organization_id:, provider_payment_id:, status:, metadata: {})
        payment = Payment.find_by(provider_payment_id:)
        return handle_missing_payment(organization_id, metadata) unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status:)

        update_invoice_payment_status(
          payment_status: invoice_payment_status(status),
          processing: status == 'processing',
        )

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def client
        @client ||= Pinet::Client.new(api_key: pinet_api_key)
      end

      def should_process_payment?
        return false if invoice.succeeded? || invoice.voided?
        return false if organization.pinet_payment_provider.blank?

        customer&.pinet_customer&.provider_customer_id
      end

      def pinet_api_key
        organization.pinet_payment_provider.secret_key
      end

      def create_pinet_payment
        client.charge(pinet_payment_payload)
      rescue StandardError => e
        deliver_error_webhook(e)
        update_invoice_payment_status(payment_status: :failed, deliver_webhook: false)
        nil
      end

      def pinet_payment_payload
        {
          payment_token: customer.pinet_customer.payment_token,
          amount: invoice.total_amount_cents,
          currency: invoice.currency.downcase,
        }
      end

      def invoice_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status&.to_sym
      end

      def update_invoice_payment_status(payment_status:, deliver_webhook: true, processing: false)
        result = Invoices::UpdateService.call(
          invoice: invoice.presence || @result.invoice,
          params: {
            payment_status:,
            # NOTE: A proper `processing` payment status should be introduced for invoices
            ready_for_payment_processing: !processing && payment_status.to_sym != :succeeded,
          },
          webhook_notification: deliver_webhook,
        )
        result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(pinet_error)
        return unless invoice.organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.pinet_customer.provider_customer_id,
          provider_error: {
            message: pinet_error.message,
            error_code: pinet_error.code,
          },
        )
      end

      def handle_missing_payment(organization_id, metadata)
        # NOTE: Payment was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belong to this lago organization
        #       It means the same Stripe secret key is used for multiple organizations
        invoice = Invoice.find_by(id: metadata[:lago_invoice_id], organization_id:)
        return result if invoice.nil?

        # NOTE: Invoice exists but status is failed
        return result if invoice.failed?

        result.not_found_failure!(resource: 'pinet_payment')
      end
    end
  end
end
