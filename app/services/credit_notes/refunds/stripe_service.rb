# frozen_string_literal: true

module CreditNotes
  module Refunds
    class StripeService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        stripe_result = create_stripe_refund

        refund = Refund.new(
          credit_note:,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment.payment_provider_customer,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          status: stripe_result.status,
          provider_refund_id: stripe_result.id
        )
        refund.save!

        update_credit_note_status(refund.status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        result.refund = refund
        result
      end

      def update_status(provider_refund_id:, status:, metadata: {})
        refund = Refund.find_by(provider_refund_id:)
        return handle_missing_refund(metadata) unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        refund.update!(status:)
        update_credit_note_status(status)
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        if status.to_sym == :failed
          deliver_error_webhook(message: 'Payment refund failed', code: nil)
          result.service_failure!(code: 'refund_failed', message: 'Refund failed to perform')
        end

        result
      rescue ArgumentError
        result.single_validation_failure!(field: :refund_status, error_code: 'value_is_invalid')
      end

      private

      attr_accessor :credit_note

      delegate :organization, :customer, :invoice, to: :credit_note

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present?
      end

      def payment
        @payment ||= credit_note.invoice.payments.order(created_at: :desc).first
      end

      def stripe_api_key
        stripe_payment_provider.secret_key
      end

      def create_stripe_refund
        Stripe::Refund.create(
          stripe_refund_payload,
          {
            api_key: stripe_api_key,
            idempotency_key: credit_note.id
          }
        )
      rescue Stripe::InvalidRequestError => e
        deliver_error_webhook(message: e.message, code: e.code)
        update_credit_note_status(:failed)

        raise
      end

      def stripe_refund_payload
        {
          payment_intent: payment.provider_payment_id,
          amount: credit_note.refund_amount_cents,
          reason: stripe_reason,
          metadata: {
            lago_customer_id: customer.id,
            lago_credit_note_id: credit_note.id,
            lago_invoice_id: invoice.id
          }
        }
      end

      def stripe_reason
        case credit_note.reason.to_sym
        when :duplicated_charge
          :duplicate
        when :product_unsatisfactory, :order_change, :order_cancellation
          :requested_by_customer
        when :fraudulent_charge
          :fraudulent
        end
      end

      def deliver_error_webhook(message:, code:)
        SendWebhookJob.perform_later(
          'credit_note.provider_refund_failure',
          credit_note,
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def handle_missing_refund(metadata)
        # NOTE: Refund was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belongs to this lago instance
        return result unless Invoice.find_by(id: metadata[:lago_invoice_id])

        result.not_found_failure!(resource: 'stripe_refund')
      end

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
