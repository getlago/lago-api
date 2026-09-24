# frozen_string_literal: true

module X402
  module CreditPurchases
    # D4 phase 2, D2: the credit invoice of an x402 purchase is paid by the settlement that funded it — an x402
    # Payment carrying the transaction hash, no PSP. The wallet transaction is already settled, so the prepaid-credit
    # callback this triggers returns early (ApplyPaidCreditsService's settled guard) and nothing is granted twice.
    class RecordPaymentService < BaseService
      Result = BaseResult[:payment]

      def initialize(invoice:, wallet_transaction:)
        @invoice = invoice
        @wallet_transaction = wallet_transaction
        super
      end

      def call
        settlement = ::X402::Settlement.find_by!(wallet_transaction:)

        ActiveRecord::Base.transaction do
          result.payment = invoice.payments.create!(
            organization_id: invoice.organization_id,
            customer_id: invoice.customer_id,
            amount_cents: invoice.total_amount_cents,
            amount_currency: invoice.currency,
            status: "succeeded",
            payable_payment_status: "succeeded",
            payment_type: :x402,
            provider_payment_id: settlement.transaction_hash
          )

          # The same flip Invoices::Payments::CreateService#update_invoice_payment_status makes for a PSP success.
          ::Invoices::UpdateService.call!(
            invoice:,
            params: {
              payment_status: :succeeded,
              ready_for_payment_processing: false,
              total_paid_amount_cents: invoice.payments.where(payable_payment_status: :succeeded).sum(:amount_cents)
            },
            webhook_notification: true
          )
        end

        after_commit do
          ::PaymentReceipts::CreateJob.perform_later(result.payment) if invoice.organization.issue_receipts_enabled?
        end

        result
      end

      private

      attr_reader :invoice, :wallet_transaction
    end
  end
end
