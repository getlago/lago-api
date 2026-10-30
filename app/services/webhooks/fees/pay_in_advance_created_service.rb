# frozen_string_literal: true

module Webhooks
  module Fees
    class PayInAdvanceCreatedService < Webhooks::BaseService
      private

      def object_serializer
        if object.product?
          # A webhook cannot ask for expansions: it carries the fee's tax lines.
          ::V2::FeeSerializer.new(object, root_name: "fee", includes: %i[applied_taxes])
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
