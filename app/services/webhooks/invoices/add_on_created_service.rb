# frozen_string_literal: true

module Webhooks
  module Invoices
    class AddOnCreatedService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::InvoiceSerializer.new(
          object,
          root_name: 'invoice',
          includes: %i[customer subscriptions fees],
        )
      end

      def webhook_type
        'invoice.add_on_added'
      end

      def object_type
        'invoice'
      end
    end
  end
end
