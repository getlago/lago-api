# frozen_string_literal: true

module V1
  module Legacy
    class CreditNoteSerializer < ModelSerializer
      def serialize
        {
          total_amount_currency: model.total_amount_currency,
          vat_amount_cents: model.taxes_amount_cents,
          vat_amount_currency: model.currency,
          sub_total_vat_excluded_amount_cents: model.sub_total_excluding_taxes_amount_cents,
          sub_total_vat_excluded_amount_currency: model.currency,
          balance_amount_currency: model.balance_amount_currency,
          credit_amount_currency: model.credit_amount_currency,
          refund_amount_currency: model.refund_amount_currency
        }
      end
    end
  end
end
