# frozen_string_literal: true

module Webhooks
  module Orders
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::OrderSerializer.new(object, root_name: "order")
      end

      def webhook_type
        "order.created"
      end

      def object_type
        "order"
      end
    end
  end
end
