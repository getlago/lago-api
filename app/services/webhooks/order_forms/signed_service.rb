# frozen_string_literal: true

module Webhooks
  module OrderForms
    class SignedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::OrderFormSerializer.new(object, root_name: "order_form")
      end

      def webhook_type
        "order_form.signed"
      end

      def object_type
        "order_form"
      end
    end
  end
end
