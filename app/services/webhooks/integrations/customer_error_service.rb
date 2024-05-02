# frozen_string_literal: true

module Webhooks
  module Integrations
    class CustomerErrorService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

      def object_serializer
        ::V1::Integrations::CustomerErrorSerializer.new(
          object,
          root_name: object_type,
          provider_error: options[:provider_error],
          provider: options[:provider],
        )
      end

      def webhook_type
        'customer.accounting_provider_error'
      end

      def object_type
        'accounting_provider_customer_error'
      end
    end
  end
end
