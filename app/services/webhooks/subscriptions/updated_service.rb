# frozen_string_literal: true

module Webhooks
  module Subscriptions
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::SubscriptionSerializer.new(
          object,
          root_name: "subscription",
          includes: %i[plan customer entitlements]
        )
      end

      def webhook_type
        "subscription.updated"
      end

      def object_type
        "subscription"
      end

      # Groups every change to one customer onto a single Kinesis shard, so a
      # consumer can process that customer's records on one worker.
      def partition_key
        object.customer.external_id
      end
    end
  end
end
