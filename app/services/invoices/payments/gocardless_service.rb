# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessService < BaseService
      PENDING_STATUSES = %w[pending_customer_approval pending_submission submitted confirmed].freeze
      SUCCESS_STATUSES = %w[paid_out].freeze
      FAILED_STATUSES = %w[cancelled customer_approval_denied failed charged_back].freeze

      def initialize(invoice = nil)
        @invoice = invoice

        super(nil)
      end

      def create
        result.invoice = invoice
        return result unless should_process_payment?

        unless invoice.total_amount_cents.positive?
          update_invoice_status(:succeeded)
          return result
        end

        gocardless_result = create_gocardless_payment

        payment = Payment.new(
          invoice: invoice,
          payment_provider_id: organization.gocardless_payment_provider.id,
          payment_provider_customer_id: customer.gocardless_customer.id,
          amount_cents: gocardless_result.amount,
          amount_currency: gocardless_result.currency&.upcase,
          provider_payment_id: gocardless_result.id,
          status: gocardless_result.status,
        )
        payment.save!

        invoice_status = invoice_status(payment.status)
        update_invoice_status(invoice_status)
        handle_prepaid_credits(invoice_status)
        track_payment_status_changed(payment.invoice)

        result.payment = payment
        result
      end

      def update_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id: provider_payment_id)
        return result.not_found_failure!(resource: 'gocardless_payment') unless payment

        result.payment = payment
        result.invoice = payment.invoice
        return result if payment.invoice.succeeded?

        payment.update!(status: status)

        invoice_status = invoice_status(status)
        payment.invoice.update!(status: invoice_status)
        handle_prepaid_credits(invoice_status)
        track_payment_status_changed(payment.invoice)

        result
      rescue ArgumentError
        result.single_validation_failure!(field: :status, error_code: 'value_is_invalid')
      end

      private

      attr_accessor :invoice

      delegate :organization, :customer, to: :invoice

      def should_process_payment?
        return false if invoice.succeeded?
        return false if organization.gocardless_payment_provider.blank?
        return false if customer&.gocardless_customer&.provider_customer_id.blank?
        return false if customer&.gocardless_customer&.provider_mandate_id.blank?

        true
      end

      def client
        @client ||= GoCardlessPro::Client.new(access_token: access_token, environment: :sandbox)
      end

      def access_token
        organization.gocardless_payment_provider.access_token
      end

      def create_gocardless_payment
        client.payments.create(
          params: {
            amount: invoice.total_amount_cents,
            currency: invoice.total_amount_currency.upcase,
            reference: invoice.id,
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601,
            },
            links: {
              mandate: customer.gocardless_customer.provider_mandate_id,
            },
          },
          headers: {
            'Idempotency-Key' => invoice.id,
          },
        )
      rescue GoCardlessPro::Error => e
        deliver_error_webhook(e)
        update_invoice_status(:failed)

        raise
      end

      def invoice_status(status)
        return 'pending' if PENDING_STATUSES.include?(status)
        return 'succeeded' if SUCCESS_STATUSES.include?(status)
        return 'failed' if FAILED_STATUSES.include?(status)

        status
      end

      def update_invoice_status(status)
        return unless Invoice::STATUS.include?(status&.to_sym)

        invoice.update!(status: status)
      end

      def handle_prepaid_credits(invoice_status)
        return unless invoice.invoice_type == 'credit'
        return unless invoice_status == 'succeeded'

        Invoices::PrepaidCreditJob.perform_later(invoice)
      end

      def deliver_error_webhook(gocardless_error)
        return unless invoice.organization.webhook_url?

        SendWebhookJob.perform_later(
          :payment_provider_invoice_payment_error,
          invoice,
          provider_customer_id: customer.gocardless_customer.provider_customer_id,
          provider_error: {
            message: gocardless_error.message,
            error_code: gocardless_error.code,
          },
        )
      end

      def track_payment_status_changed(invoice)
        SegmentTrackJob.perform_later(
          membership_id: CurrentContext.membership,
          event: 'payment_status_changed',
          properties: {
            organization_id: invoice.organization.id,
            invoice_id: invoice.id,
            payment_status: invoice.status,
          },
        )
      end
    end
  end
end
