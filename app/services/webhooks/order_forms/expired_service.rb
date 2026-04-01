# frozen_string_literal: true

module Webhooks
  module OrderForms
    class ExpiredService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::OrderFormSerializer.new(object, root_name: "order_form")
      end

      def webhook_type
        "order_form.expired"
      end

      def object_type
        "order_form"
      end
    end
  end
end
