# frozen_string_literal: true

module CreditNotes
  module Refunds
    class StripeService < BaseService
      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        stripe_result = create_stripe_refund

        refund = Refund.new(
          credit_note: credit_note,
          payment: payment,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment.payment_provider_customer,
          amount_cents: stripe_result.amount,
          amount_currency: stripe_result.currency&.upcase,
          status: stripe_result.status,
          provider_refund_id: stripe_result.id,
        )
        refund.save!

        update_credit_note_status(refund.status)
        track_refund_status_changed(refund.status)

        result.refund = refund
        result
      end

      def update_status(provider_refund_id:, status:)
        refund = Refund.find_by(provider_refund_id: provider_refund_id)
        return result.not_found_failure!(resource: 'stripe_refund') unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        refund.update!(status: status)
        update_credit_note_status(status)
        track_refund_status_changed(status)

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
        return false unless credit_note.refunded?
        return false if credit_note.succeeded?

        payment.present?
      end

      def payment
        @payment ||= credit_note.invoice.payments.order(created_at: :desc).first
      end

      def stripe_api_key
        organization.stripe_payment_provider.secret_key
      end

      def create_stripe_refund
        Stripe::Refund.create(
          stripe_refund_payload,
          {
            api_key: stripe_api_key,
            idempotency_key: credit_note.id,
          },
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
          currency: credit_note.refund_amount_currency.downcase,
          reason: stripe_reason,
          metadata: {
            lago_customer_id: customer.id,
            lago_credit_note_id: credit_note.id,
            lago_invoice_id: invoice.id,
          },
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
        return unless organization.webhook_url?

        SendWebhookJob.perform_later(
          'credit_note.provider_refund_failure',
          credit_note,
          provider_customer_id: customer.stripe_customer.provider_customer_id,
          provider_error: {
            message: message,
            error_code: code,
          },
        )
      end

      def update_credit_note_status(status)
        credit_note.update!(refund_status: status)
      end

      def track_refund_status_changed(status)
        SegmentTrackJob.perform_later(
          membership_id: CurrentContext.membership,
          event: 'refund_status_change',
          properties: {
            organization_id: organization.id,
            credit_note_id: credit_note.id,
            refund_status: status,
          },
        )
      end
    end
  end
end
