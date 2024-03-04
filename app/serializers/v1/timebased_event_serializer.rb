# frozen_string_literal: true

module V1
  class TimebasedEventSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        external_customer_id: model.external_customer_id,
        timestamp: model.timestamp.iso8601(3),
        external_subscription_id: model.external_subscription_id,
        created_at: model.created_at.iso8601,
      }
    end
  end
end
