# frozen_string_literal: true

module V1
  module Customers
    class AppliedTaxSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_customer_id: model.customer.id,
          lago_tax_id: model.tax.id,
          tax_code: model.tax.code,
          external_customer_id: model.customer.external_id,
          created_at: model.created_at.iso8601,
        }
      end
    end
  end
end
