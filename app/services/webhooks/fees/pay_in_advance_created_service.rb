# frozen_string_literal: true

module Webhooks
  module Fees
    class PayInAdvanceCreatedService < Webhooks::BaseService
      private

      def object_serializer
        if object.product?
          ::V2::FeeSerializer.new(object, root_name: "fee", webhook: true)
        else
          ::V1::FeeSerializer.new(object, root_name: "fee")
        end
      end

      def webhook_type
        "fee.created"
      end

      def object_type
        "fee"
      end
    end
  end
end
