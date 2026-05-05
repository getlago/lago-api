# frozen_string_literal: true

module CreditNotes
  module Refunds
    class PaystackService < BaseService
      include Customers::PaymentProviderFinder

      PENDING_STATUSES = %w[pending processing needs-attention].freeze
      SUCCESS_STATUSES = %w[processed].freeze
      FAILED_STATUSES = %w[failed reversed].freeze

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?
        return existing_refund_result if existing_refund

        paystack_result = client.create_refund(paystack_refund_payload)
        refund_data = paystack_result["data"]

        refund = Refund.new(
          organization_id: credit_note.organization_id,
          credit_note:,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment_provider_customer(customer),
          amount_cents: refund_data["amount"],
          amount_currency: refund_data["currency"]&.upcase,
          status: refund_data["status"],
          provider_refund_id: refund_data["id"].to_s
        )
        refund.save!

        update_credit_note_status(credit_note_status(refund.status))
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        result.refund = refund
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      rescue PaymentProviders::Paystack::Client::Error => e
        deliver_error_webhook(message: e.message, code: e.code)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
        result.third_party_failure!(third_party: "Paystack", error_code: e.code, error_message: e.message)
      rescue LagoHttpClient::HttpError => e
        deliver_error_webhook(message: e.error_body, code: e.error_code)
        update_credit_note_status(:failed)
        Utils::ActivityLog.produce(credit_note, "credit_note.refund_failure")
        result.service_failure!(code: "paystack_error", message: e.message)
      end

      def update_status(status:, provider_refund_id: nil, transaction_reference: nil, metadata: {})
        refund = find_refund(provider_refund_id:, transaction_reference:)
        return handle_missing_refund(metadata) unless refund

        result.refund = refund
        @credit_note = result.credit_note = refund.credit_note
        return result if refund.credit_note.succeeded?

        refund.update!(status:)
        update_credit_note_status(credit_note_status(refund.status))
        Utils::SegmentTrack.refund_status_changed(refund.status, credit_note.id, organization.id)

        if FAILED_STATUSES.include?(status.to_s)
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

      def existing_refund
        @existing_refund ||= credit_note.refunds
          .where(payment:)
          .where(status: PENDING_STATUSES + SUCCESS_STATUSES)
          .order(created_at: :desc)
          .first
      end

      def existing_refund_result
        result.refund = existing_refund
        result
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
            .where(payment_requests: {payment_status: 1})
            .order("payments.created_at DESC")
            .first
        end
      end

      def paystack_refund_payload
        {
          transaction: payment.provider_payment_id,
          amount: credit_note.refund_amount_cents,
          currency: credit_note.refund_amount_currency&.upcase,
          customer_note: "Refund for Lago credit note #{credit_note.id}",
          merchant_note: "Lago invoice #{invoice.id}"
        }.compact
      end

      def find_refund(provider_refund_id:, transaction_reference:)
        if provider_refund_id.present?
          refund = Refund.find_by(provider_refund_id: provider_refund_id.to_s)
          return refund if refund
        end

        return if transaction_reference.blank?

        payment = Payment.find_by("provider_payment_data ->> 'reference' = ?", transaction_reference)
        return unless payment

        payment.refunds.order(created_at: :desc).first
      end

      def credit_note_status(status)
        return "pending" if PENDING_STATUSES.include?(status)
        return "succeeded" if SUCCESS_STATUSES.include?(status)
        return "failed" if FAILED_STATUSES.include?(status)

        status
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def deliver_error_webhook(message:, code:)
        SendWebhookJob.perform_later(
          "credit_note.provider_refund_failure",
          credit_note,
          provider_customer_id: payment_provider_customer(customer)&.provider_customer_id,
          provider_error: {
            message:,
            error_code: code
          }
        )
      end

      def handle_missing_refund(metadata)
        return result unless metadata&.key?(:lago_invoice_id) || metadata&.key?("lago_invoice_id")

        lago_invoice_id = metadata[:lago_invoice_id] || metadata["lago_invoice_id"]
        return result unless Invoice.find_by(id: lago_invoice_id)

        result.not_found_failure!(resource: "paystack_refund")
      end

      def client
        @client ||= PaymentProviders::Paystack::Client.new(payment_provider: paystack_payment_provider)
      end

      def paystack_payment_provider
        @paystack_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
