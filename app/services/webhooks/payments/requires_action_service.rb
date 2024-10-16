# frozen_string_literal: true

module Webhooks
  module Payments
    class RequiresActionService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.payable.organization
      end

      def object_serializer
        ::V1::Payments::RequiresActionSerializer.new(
          object,
          root_name: object_type,
          provider_customer_id: options[:provider_customer_id]
        )
      end

      def webhook_type
        'payment.requires_action'
      end

      def object_type
        'payment'
      end
    end
  end
end
