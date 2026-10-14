# frozen_string_literal: true

module X402
  module Payments
    class CreateService < BaseService
      Result = BaseResult[:payment]

      def initialize(settlement:, invoice:)
        @settlement = settlement
        @invoice = invoice

        super
      end

      def call
        settlement.with_lock(requires_new: true) do
          if !settlement.settled?
            result.single_validation_failure!(error_code: "settlement_not_settled")
          elsif paid_invoice_id != invoice.id
            result.single_validation_failure!(error_code: "settlement_invoice_mismatch")
          elsif settlement.payment
            result.payment = settlement.payment
          else
            result.payment = create_payment
          end
        end

        result
      rescue ActiveRecord::RecordInvalid => e
        settlement.reload
        invoice.reload
        result.record_validation_failure!(record: e.record)
      rescue BaseService::FailedResult => e
        settlement.reload
        invoice.reload
        result.fail_with_error!(e)
      end

      private

      attr_reader :settlement, :invoice

      def paid_invoice_id
        if settlement.payment
          settlement.payment.payable_id
        elsif settlement.invoice_payment?
          settlement.invoice_id
        else
          settlement.wallet_transaction&.invoice_id
        end
      end

      def create_payment
        payment = invoice.payments.create!(
          organization_id: invoice.organization_id,
          customer_id: invoice.customer_id,
          amount_cents: settlement.settled_amount_cents,
          amount_currency: invoice.currency,
          status: "succeeded",
          payable_payment_status: "succeeded",
          payment_type: :x402
        )
        settlement.update!(payment:)
        Invoices::UpdateService.call!(invoice:, params: invoice_params, webhook_notification: true)

        after_commit do
          SendWebhookJob.perform_later("payment.succeeded", payment)
          PaymentReceipts::CreateJob.perform_later(payment) if settlement.organization.issue_receipts_enabled?
          Integrations::Aggregator::Payments::CreateJob.perform_later(payment:) if payment.should_sync_payment?
        end

        payment
      end

      def invoice_params
        total_paid_amount_cents = invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
        total_applied_from_credit_note = invoice.invoice_settlements.where(settlement_type: :credit_note).sum(:amount_cents)

        if total_paid_amount_cents + total_applied_from_credit_note == invoice.total_amount_cents
          {total_paid_amount_cents:, payment_status: "succeeded"}
        else
          {total_paid_amount_cents:}
        end
      end
    end
  end
end
