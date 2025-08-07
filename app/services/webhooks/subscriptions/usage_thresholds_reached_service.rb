# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class UsageThresholdsReachedService < BaseService
      private

      def includes
        %i[plan customer usage_threshold]
      end

      def serialization_options
        {usage_threshold: options[:usage_threshold]}
      end

      def webhook_type
        "subscription.usage_threshold_reached"
      end
    end
  end
end
