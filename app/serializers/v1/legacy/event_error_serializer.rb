# frozen_string_literal: true

module V1
  module Legacy
    class EventErrorSerializer < ModelSerializer
      def serialize
        {
          input_params: {
            transaction_id: model.transaction_id,
            external_subscription_id: model.external_subscription_id,
            external_customer_id: model.external_customer_id,
            timestamp: model.timestamp.to_f,
            code: model.code,
            properties: model.properties
          }
        }
      end
    end
  end
end
