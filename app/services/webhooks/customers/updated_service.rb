# frozen_string_literal: true

module Webhooks
  module Customers
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::CustomerSerializer.new(
          object,
          root_name: "customer",
          includes: %i[integration_customers]
        )
      end

      def webhook_type
        "customer.updated"
      end

      def object_type
        "customer"
      end

      # Groups every change to one customer onto a single Kinesis shard, so a
      # consumer can process that customer's records on one worker.
      def partition_key
        object.external_id
      end
    end
  end
end
