# frozen_string_literal: true

module V1
  class CustomerSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        customer_id: model.customer_id,
        name: model.name,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
