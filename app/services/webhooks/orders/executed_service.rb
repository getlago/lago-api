# frozen_string_literal: true

module Webhooks
  module Orders
    class ExecutedService < Webhooks::BaseService
      include Webhooks::OrderFormsGate

      private

      def object_serializer
        ::V1::OrderSerializer.new(object, root_name: "order")
      end

      def webhook_type
        "order.executed"
      end

      def object_type
        "order"
      end
    end
  end
end
