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

      def initialize(payable = nil)
        @payable = payable

        super(nil)
      end

      def update_payment_status(provider_payment_id:, status:)
        payment = Payment.find_by(provider_payment_id:)
        return result.not_found_failure!(resource: 'gocardless_payment') unless payment

        result.payment = payment
        result.payable = payment.payable
        return result if payment.payable.payment_succeeded?

        payment.update!(status:)

        payable_payment_status = payment.payment_provider.determine_payment_status(status)
        update_payable_payment_status(payment_status: payable_payment_status)
        update_invoices_payment_status(payment_status: payable_payment_status)
        reset_customer_dunning_campaign_status(payable_payment_status)

        PaymentRequestMailer.with(payment_request: payment.payable).requested.deliver_later if result.payable.payment_failed?

        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_accessor :payable

      delegate :organization, :customer, to: :payable

      def client
        @client ||= GoCardlessPro::Client.new(
          access_token: gocardless_payment_provider.access_token,
          environment: gocardless_payment_provider.environment
        )
      end

      def gocardless_payment_provider
        @gocardless_payment_provider ||= payment_provider(customer)
      end

<<<<<<< HEAD
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
              lago_payable_id: payable.id,
              lago_payable_type: payable.class.name
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

        result.service_failure!(code: e.code, message: e.message)
        nil
=======
      def payable_payment_status(payment_status)
        return :pending if PENDING_STATUSES.include?(payment_status)
        return :succeeded if SUCCESS_STATUSES.include?(payment_status)
        return :failed if FAILED_STATUSES.include?(payment_status)

        payment_status
>>>>>>> e049a84a (misc(PaymentRequest): Re-use payment logic for request)
      end

      def update_payable_payment_status(payment_status:, deliver_webhook: true)
        UpdateService.call(
          payable: result.payable,
          params: {
            payment_status:,
            ready_for_payment_processing: !payment_status_succeeded?(payment_status)
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
              ready_for_payment_processing: !payment_status_succeeded?(payment_status)
            },
            webhook_notification: deliver_webhook
          ).raise_if_error!
        end
      end

      def payment_status_succeeded?(payment_status)
        payment_status.to_sym == :succeeded
      end

      def reset_customer_dunning_campaign_status(payment_status)
        return unless payment_status_succeeded?(payment_status)
        return unless payable.try(:dunning_campaign)

        customer.reset_dunning_campaign!
      end
    end
  end
end
