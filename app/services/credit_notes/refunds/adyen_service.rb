# frozen_string_literal: true

module CreditNotes
  module Refunds
    class AdyenService < BaseService
      include Customers::PaymentProviderFinder

      def initialize(credit_note = nil)
        @credit_note = credit_note

        super
      end

      def create
        result.credit_note = credit_note
        return result unless should_process_refund?

        adyen_result = create_adyen_refund

        refund = Refund.new(
          credit_note:,
          payment:,
          payment_provider: payment.payment_provider,
          payment_provider_customer: payment.payment_provider_customer,
          amount_cents: adyen_result.response.dig('amount', 'value'),
          amount_currency: adyen_result.response.dig('amount', 'currency'),
          status: 'pending',
          provider_refund_id: adyen_result.response['pspReference'],
        )
        refund.save!

        update_credit_note_status(refund.status)
        track_refund_status_changed(refund.status)

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

      def client
        @client ||= Adyen::Client.new(
          api_key: payment.payment_provider.api_key,
          env: payment.payment_provider.environment,
          live_url_prefix: payment.payment_provider.live_prefix,
        )
      end

      def should_process_refund?
        return false if !credit_note.refunded? || credit_note.succeeded? || invoice.payment_dispute_lost_at?

        payment.present?
      end

      def payment
        @payment ||= credit_note.invoice.payments.order(created_at: :desc).first
      end

      def adyen_api_key
        adyen_payment_provider.secret_key
      end

      def create_adyen_refund
        client.checkout.modifications_api.refund_captured_payment(
          Lago::Adyen::Params.new(adyen_refund_params).to_h,
          payment.provider_payment_id,
        )
      rescue Adyen::AdyenError => e
        deliver_error_webhook(message: e.msg, code: e.code)
        update_credit_note_status(:failed)

        raise
      end

      def adyen_refund_params
        {
          paymentPspReference: payment.provider_payment_id,
          merchantAccount: payment.payment_provider.merchant_account,
          amount: {
            value: credit_note.refund_amount_cents,
            currency: credit_note.credit_amount_currency.upcase,
          },
        }
      end

      def deliver_error_webhook(message:, code:)
        return unless organization.webhook_endpoints.any?

        SendWebhookJob.perform_later(
          'credit_note.provider_refund_failure',
          credit_note,
          provider_customer_id: customer.adyen_customer.provider_customer_id,
          provider_error: {
            message:,
            error_code: code,
          },
        )
      end

      def update_credit_note_status(status)
        credit_note.refund_status = status
        credit_note.refunded_at = Time.current if credit_note.succeeded?
        credit_note.save!
      end

      def track_refund_status_changed(status)
        SegmentTrackJob.perform_later(
          membership_id: CurrentContext.membership,
          event: 'refund_status_changed',
          properties: {
            organization_id: organization.id,
            credit_note_id: credit_note.id,
            refund_status: status,
          },
        )
      end

      def handle_missing_refund(metadata)
        # NOTE: Refund was not initiated by lago
        return result unless metadata&.key?(:lago_invoice_id)

        # NOTE: Invoice does not belongs to this lago instance
        return result unless Invoice.find_by(id: metadata[:lago_invoice_id])

        result.not_found_failure!(resource: 'adyen_refund')
      end

      def adyen_payment_provider
        @adyen_payment_provider ||= payment_provider(customer)
      end
    end
  end
end
