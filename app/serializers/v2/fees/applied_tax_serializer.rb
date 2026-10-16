# frozen_string_literal: true

module V2
  module Fees
    class AppliedTaxSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_fee_id: model.fee_id,
          lago_tax_id: model.tax_id,
          tax_name: model.tax_name,
          tax_code: model.tax_code,
          tax_rate: model.tax_rate,
          tax_description: model.tax_description,
          amount_cents: model.amount_cents
        }
      end
    end
  end
end
