# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class TerminatedService < Webhooks::BaseService
      def object_serializer
        ::V1::SubscriptionSerializer.new(
          object,
          root_name: 'subscription',
        )
      end

      def webhook_type
        'subscription.terminated'
      end

      def object_type
        'invoice'
      end
    end
  end
end
