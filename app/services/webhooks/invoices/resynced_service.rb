# frozen_string_literal: true

module Webhooks
  module Invoices
    class ResyncedService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::InvoiceSerializer.new(
          object,
          root_name: 'invoice',
          includes: %i[customer subscriptions fees credits applied_taxes]
        )
      end

      def webhook_type
        'invoice.resynced'
      end

      def object_type
        'invoice'
      end
    end
  end
end