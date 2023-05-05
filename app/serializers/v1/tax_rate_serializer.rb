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
        customers_count:,
        created_at: model.created_at.iso8601,
      }
    end

    private

    def customers_count
      # TODO: Not yet implemented.
      0
    end
  end
end
