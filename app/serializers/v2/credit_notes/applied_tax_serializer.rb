# frozen_string_literal: true

module V2
  module CreditNotes
    class AppliedTaxSerializer < ModelSerializer
      def serialize
        {
          lago_tax_id: model.tax_id,
          tax_name: model.tax_name,
          tax_code: model.tax_code,
          tax_rate: model.tax_rate,
          tax_description: model.tax_description,
          base_amount_cents: model.base_amount_cents,
          amount_cents: model.amount_cents,
          currency: model.amount_currency
        }
      end
    end
  end
end
