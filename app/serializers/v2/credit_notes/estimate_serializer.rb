# frozen_string_literal: true

module V2
  module CreditNotes
    class EstimateSerializer < ModelSerializer
      expandable :items, serializer: ::V2::CreditNotes::ItemSerializer
      expandable :applied_taxes, serializer: ::V2::CreditNotes::AppliedTaxSerializer

      def serialize
        {
          lago_invoice_id: model.invoice_id,
          invoice_number: model.invoice.number,
          currency: model.currency,
          sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents,
          taxes_amount_cents: model.taxes_amount_cents,
          sub_total_including_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents + model.taxes_amount_cents,
          total_amount_cents: model.total_amount_cents,
          max_creditable_amount_cents: model.credit_amount_cents,
          max_refundable_amount_cents: model.refund_amount_cents
        }
      end
    end
  end
end
