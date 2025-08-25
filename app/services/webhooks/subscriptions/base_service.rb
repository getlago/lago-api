# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class BaseService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::SubscriptionSerializer.new(
          object,
          root_name: "subscription",
          includes: includes,
          **serialization_options
        )
      end

      def includes
        %i[plan customer]
      end

      def serialization_options
        {}
      end

      def object_type
        "subscription"
      end
    end
  end
end
