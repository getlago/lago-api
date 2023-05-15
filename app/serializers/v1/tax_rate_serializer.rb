# frozen_string_literal: true

module V1
  class TaxRateSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        value: model.value,
        description: model.description,
        applied_by_default: model.applied_by_default,
        customers_count: model.customers_count,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
