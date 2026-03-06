# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    class RefundExpiredPaymentService < BaseService
      Result = BaseResult[:credit_note]

      def initialize(invoice:)
        @invoice = invoice

        super
      end

      def call
        # Finalize the invoice first so it can be refunded via credit note.
        # Gated invoices are in `open` status and credit notes require a finalized invoice.
        Invoices::FinalizeService.call!(invoice:)

        credit_note_result = CreditNotes::CreateService.call(
          invoice:,
          reason: :order_cancellation,
          description: "Automatic refund: payment received after subscription activation expired",
          refund_amount_cents: invoice.total_amount_cents,
          credit_amount_cents: 0,
          items: credit_note_items,
          automatic: true
        )

        result.credit_note = credit_note_result.credit_note
        result
      end

      private

      attr_reader :invoice

      def credit_note_items
        invoice.fees.map do |fee|
          {
            fee_id: fee.id,
            amount_cents: fee.amount_cents
          }
        end
      end
    end
  end
end
