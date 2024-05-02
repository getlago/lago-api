# frozen_string_literal: true

module Webhooks
  module Integrations
    class CustomerCreatedService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::CustomerSerializer.new(
          object,
          root_name: object_type,
        )
      end

      def webhook_type
        'customer.accounting_provider_created'
      end

      def object_type
        'customer'
      end
    end
  end
end
