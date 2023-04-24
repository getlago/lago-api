# frozen_string_literal: true

module V1
  module Legacy
    class CreditNoteSerializer < ModelSerializer
      def serialize
        {
          total_amount_currency: model.total_amount_currency,
          vat_amount_currency: model.vat_amount_currency,
          sub_total_vat_excluded_amount_currency: model.sub_total_vat_excluded_amount_currency,
          balance_amount_currency: model.balance_amount_currency,
          credit_amount_currency: model.credit_amount_currency,
          refund_amount_currency: model.refund_amount_currency,
        }
      end
    end
  end
end
