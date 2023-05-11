# frozen_string_literal: true

module V1
  class AppliedTaxRateSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_customer_id: model.customer.id,
        lago_tax_rate_id: model.tax_rate.id,
        tax_rate_code: model.tax_rate.code,
        external_customer_id: model.customer.external_id,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
