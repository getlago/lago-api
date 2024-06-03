# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[pending_customer_approval pending_submission submitted confirmed]
        .freeze
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
          update_invoice_payment_status(payment_status: :succeeded)
          return result
        end

        increment_payment_attempts

        gocardless_result = create_gocardless_payment

        payment = Payment.new(
          invoice:,
          payment_provider_id: gocardless_payment_provider.id,
          payment_provider_customer_id: customer.gocardless_customer.id,
          amount_cents: gocardless_result.amount,
          amount_currency: gocardless_result.currency&.upcase,
          provider_payment_id: gocardless_result.id,
          status: gocardless_result.status
        )
        payment.save!

        invoice_payment_status = invoice_payment_status(payment.status)
        update_invoice_payment_status(payment_status: invoice_payment_status)

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: 'gocardless_payment') unless payment

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
        return false if invoice.succeeded? || invoice.voided?
        return false if gocardless_payment_provider.blank?

        customer&.gocardless_customer&.provider_customer_id
      end

      def client
        @client ||= GoCardlessPro::Client.new(
          access_token: gocardless_payment_provider.access_token,
          environment: gocardless_payment_provider.environment
        )
      end

      def gocardless_payment_provider
        @gocardless_payment_provider ||= payment_provider(customer)
      end

      def mandate_id
        result = client.mandates.list(
          params: {
            customer: customer.gocardless_customer.provider_customer_id,
            status: %w[pending_customer_approval pending_submission submitted active]
          }
        )

        mandate = result&.records&.first

        customer.gocardless_customer.provider_mandate_id = mandate&.id
        customer.gocardless_customer.save!

        mandate&.id
      end

      def create_gocardless_payment
        client.payments.create(
          params: {
            amount: invoice.total_amount_cents,
            currency: invoice.currency.upcase,
            retry_if_possible: false,
            metadata: {
              lago_customer_id: customer.id,
              lago_invoice_id: invoice.id,
              invoice_issuing_date: invoice.issuing_date.iso8601
            },
            links: {
              mandate: mandate_id
            }
          },
          headers: {
            'Idempotency-Key' => "#{invoice.id}/#{invoice.payment_attempts}"
          }
        )
      rescue GoCardlessPro::Error => e
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
        update_invoice_result = Invoices::UpdateService.call(
          invoice: result.invoice,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        )
        update_invoice_result.raise_if_error!
      end

      def increment_payment_attempts
        invoice.update!(payment_attempts: invoice.payment_attempts + 1)
      end

      def deliver_error_webhook(gocardless_error)
        return unless invoice.organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          'invoice.payment_failure',
          invoice,
          provider_customer_id: customer.gocardless_customer.provider_customer_id,
          provider_error: {
            message: gocardless_error.message,
            error_code: gocardless_error.code
          }
        )
      end
    end
  end
end
