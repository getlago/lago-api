# frozen_string_literal: true
#
module V1
  class EventSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        transaction_id: model.transaction_id,
        customer_id: model.customer_id,
        code: model.code,
        timestamp: model.timestamp.iso8601,
        properties: model.properties,
        created_at: model.created_at.iso8601
      }
    end
  end
end
