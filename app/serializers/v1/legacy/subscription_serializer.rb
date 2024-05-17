# frozen_string_literal: true

module V1
  module Legacy
    class SubscriptionSerializer < ModelSerializer
      def serialize
        {
          subscription_date: model.subscription_at&.to_date
        }
      end
    end
  end
end
