# frozen_string_literal: true

module CreditNotes
  module Refunds
    class StripeService < BaseService
      Result = BaseResult[:credit_note, :refund]

      include Customers::PaymentProviderFinder

      INVALID_PAYMENT_METHOD_ERROR = "charge_not_refundable"
      CHARGE_DISPUTED_ERROR = "charge_disputed"
      CHARGE_ALREADY_REFUNDED_ERROR = "charge_already_refunded"
      # NOTE: lago-specific, stripe rejects an over-refund without an error code
      INSUFFICIENT_REFUNDABLE_AMOUNT_ERROR = "insufficient_refundable_amount"

      NON_RETRYABLE_ERRORS = [
        INVALID_PAYMENT_METHOD_ERROR,
        CHARGE_DISPUTED_ERROR,
        CHARGE_ALREADY_REFUNDED_ERROR
      ].freeze

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        blocking_error_code = refund_blocked_error_code
        if blocking_error_code
          handle_refund_failure(message: refund_blocked_message(blocking_error_code), code: blocking_error_code)
          return result
        end

        stripe_result = create_stripe_refund

        refund = Refund.new(
          organization_id: credit_note.organization_id,
          credit_note:,
          refundable: credit_note,
          reason: :credit_note,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment_provider_customer(payment),
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
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue ::Stripe::InvalidRequestError => e
        handle_refund_failure(message: e.message, code: e.code)
        return result if NON_RETRYABLE_ERRORS.include?(e.code)

        result.service_failure!(code: "stripe_error", message: e.message)
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
          deliver_error_webhook(message: "Payment refund failed", code: nil)
          Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
          result.service_failure!(code: "refund_failed", message: "Refund failed to perform")
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_accessor :credit_note

      delegate :organization, :customer, :invoice, to: :credit_note

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present?
      end

      def payment
        return @payment if defined?(@payment)

        @payment = if credit_note.invoice.payments.succeeded.present?
          credit_note.invoice.payments.succeeded.order(created_at: :desc).first
        else
          Payment.where(payable_type: "PaymentRequest")
            .joins("INNER JOIN invoices_payment_requests ON invoices_payment_requests.payment_request_id = payments.payable_id")
            .joins("INNER JOIN payment_requests ON payment_requests.id = invoices_payment_requests.payment_request_id")
            .where("invoices_payment_requests.invoice_id = ?", credit_note.invoice_id)
            .where(payments: {payable_payment_status: "succeeded"})
            .where(payment_requests: {customer_id: credit_note.customer_id})
            .where(payment_requests: {payment_status: 1}) # 1 is succeeded
            .order("payments.created_at DESC")
            .first
        end
      end

      def refund_blocked_error_code
        return CHARGE_DISPUTED_ERROR if invoice.payment_refund_blocked_at?

        remaining = stripe_refundable_amount_cents
        # NOTE: nil means stripe could not be asked. The pre-check is an optimisation, never a
        #       gate: when in doubt we let Stripe::Refund.create decide.
        return nil if remaining.nil?
        return CHARGE_ALREADY_REFUNDED_ERROR if remaining <= 0
        return INSUFFICIENT_REFUNDABLE_AMOUNT_ERROR if remaining < credit_note.refund_amount_cents

        nil
      end

      def refund_blocked_message(code)
        case code
        when CHARGE_DISPUTED_ERROR
          "The charge is disputed and cannot be refunded"
        when CHARGE_ALREADY_REFUNDED_ERROR
          "The charge has already been fully refunded"
        when INSUFFICIENT_REFUNDABLE_AMOUNT_ERROR
          "The charge has only #{stripe_refundable_amount_cents} cents left to refund, " \
            "#{credit_note.refund_amount_cents} are required"
        end
      end

      def stripe_refundable_amount_cents
        return @stripe_refundable_amount_cents if defined?(@stripe_refundable_amount_cents)

        charge = stripe_charge
        # NOTE: bracket access, stripe objects raise NoMethodError on fields absent from the
        #       pinned API version.
        captured = charge && (charge[:amount_captured] || charge[:amount])
        refunded = charge && charge[:amount_refunded]

        @stripe_refundable_amount_cents = if captured.nil? || refunded.nil?
          nil
        else
          captured - refunded
        end
      end

      def stripe_charge
        return @stripe_charge if defined?(@stripe_charge)
        # NOTE: manual payments have no provider payment id, and Stripe::Charge.list would then
        #       silently return the whole account's charges instead of filtering.
        return @stripe_charge = nil if payment.provider_payment_id.blank?

        charges = ::Stripe::Charge.list(
          {payment_intent: payment.provider_payment_id, limit: 10},
          {api_key: stripe_api_key}
        )
        # NOTE: a payment intent can carry failed attempts alongside the successful charge.
        @stripe_charge = charges.data.detect { |charge| charge[:status] == "succeeded" }
      rescue ::Stripe::StripeError => e
        Rails.logger.warn("Unable to retrieve stripe charge for payment #{payment.id}: #{e.message}")
        @stripe_charge = nil
      end

      def handle_refund_failure(message:, code:)
        deliver_error_webhook(message:, code:)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
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
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: payment_provider_customer(payment)&.provider_customer_id,
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

        result.not_found_failure!(resource: "stripe_refund")
      end

      def stripe_payment_provider
        @stripe_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
