# frozen_string_literal: true

module Webhooks
  module Invoices
    class PaymentRequiresActionsService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::InvoicesSerializer.new(
          object,
          root_name: object_type,
          includes: [:customer]
        )
      end

      def webhook_type
        'invoice.payment_requires_action'
      end

      def object_type
        'invoice_payment_requires_action'
      end
    end
  end
end
