# frozen_string_literal: true

module Webhooks
  module PaymentReceipts
    class GeneratedService < Webhooks::BaseService
      def current_organization
        @current_organization ||= object.payment.payable.organization
      end

      def object_serializer
        ::V1::PaymentReceiptSerializer.new(
          object,
          root_name: "payment_receipt"
        )
      end

      def webhook_type
        "payment_receipt.generated"
      end

      def object_type
        "payment_receipt"
      end
    end
  end
end
