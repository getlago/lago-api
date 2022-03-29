# frozen_string_literal: true

module V1
  class CustomerSerializer < ModelSerializer
    def serialize
      {
        id: model.id,
        customer_id: model.customer_id,
        name: model.name,
        created_at: model.created_at
      }
    end
  end
end
