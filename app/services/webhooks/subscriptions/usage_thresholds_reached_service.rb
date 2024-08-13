# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class UsageThresholdsReachedService < Webhooks::BaseService
      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::SubscriptionSerializer.new(
          object,
          root_name: 'subscription',
          includes: %i[plan customer usage_threshold],
          usage_threshold: options[:usage_threshold]
        )
      end

      def webhook_type
        'subscription.usage_threshold_reached'
      end

      def object_type
        'subscription'
      end
    end
  end
end
