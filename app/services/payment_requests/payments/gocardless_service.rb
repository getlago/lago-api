# frozen_string_literal: true

module PaymentRequests
  module Payments
    class GocardlessService < BaseService
      include Customers::PaymentProviderFinder

      class MandateNotFoundError < StandardError
        DEFAULT_MESSAGE = "No mandate available for payment"
        ERROR_CODE = "no_mandate_error"

        def initialize(msg = DEFAULT_MESSAGE)
          super
        end

        def code
          ERROR_CODE
        end
      end

      PENDING_STATUSES = %w[pending_customer_approval pending_submission submitted confirmed]
        .freeze
      SUCCESS_STATUSES = %w[paid_out].freeze
      FAILED_STATUSES = %w[cancelled customer_approval_denied failed charged_back].freeze

      def initialize(payable = nil)
        @payable = payable

        super(nil)
      end

      def create
        result.payable = payable
        return result unless should_process_payment?

        unless payable.total_amount_cents.positive?
          update_payable_payment_status(payment_status: :succeeded)
          return result
        end

        payable.increment_payment_attempts!

        gocardless_result = create_gocardless_payment

        payment = Payment.new(
          payable: payable,
          payment_provider_id: gocardless_payment_provider.id,
          payment_provider_customer_id: customer.gocardless_customer.id,
          amount_cents: gocardless_result.amount,
          amount_currency: gocardless_result.currency&.upcase,
          provider_payment_id: gocardless_result.id,
          status: gocardless_result.status
        )

        ActiveRecord::Base.transaction do
          payment.save!

          payable_payment_status = payable_payment_status(payment.status)
          update_payable_payment_status(payment_status: payable_payment_status)
          update_invoices_payment_status(payment_status: payable_payment_status)
        end

        Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?

        result.payment = payment
        result
      rescue MandateNotFoundError => e
        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)

        result.service_failure!(code: e.code, message: e.message)
        result
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: 'gocardless_payment') unless payment

        result.payment = payment
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        payable_payment_status = payable_payment_status(status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def should_process_payment?
        return false if payable.payment_succeeded?
        return false if gocardless_payment_provider.blank?

        !!customer&.gocardless_customer&.provider_customer_id
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

        raise MandateNotFoundError unless mandate

        customer.gocardless_customer.provider_mandate_id = mandate.id
        customer.gocardless_customer.save!

        mandate.id
      end

      def create_gocardless_payment
        client.payments.create(
          params: {
            amount: payable.total_amount_cents,
            currency: payable.currency.upcase,
            retry_if_possible: false,
            metadata: {
              lago_customer_id: customer.id,
              lago_payment_request_id: payable.id,
              lago_invoice_ids: payable.invoice_ids
            },
            links: {
              mandate: mandate_id
            }
          },
          headers: {
            'Idempotency-Key' => "#{payable.id}/#{payable.payment_attempts}"
          }
        )
      rescue GoCardlessPro::Error => e
        deliver_error_webhook(e)
        update_payable_payment_status(payment_status: :failed, deliver_webhook: false)

        raise
      end

      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            ready_for_payment_processing: payment_status.to_sym != :succeeded
          },
          webhook_notification: deliver_webhook
        ).raise_if_error!
      end

      def update_invoices_payment_status(payment_status:, deliver_webhook: true)
        result.payable.invoices.each do |invoice|
          Invoices::UpdateService.call(
            invoice:,
            params: {
              payment_status:,
              ready_for_payment_processing: payment_status.to_sym != :succeeded
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def deliver_error_webhook(gocardless_error)
        DeliverErrorWebhookService.call_async(payable, {
          provider_customer_id: customer.gocardless_customer.provider_customer_id,
          provider_error: {
            message: gocardless_error.message,
            error_code: gocardless_error.code
          }
        })
      end
    end
  end
end
