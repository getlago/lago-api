# frozen_string_literal: true

module Webhooks
  module Fees
    class InstantCreatedService < Webhooks::BaseService
      private

      def current_organization
        @current_organization ||= object.customer.organization
      end

      def object_serializer
        ::V1::FeeSerializer.new(
          object,
          root_name: 'fee',
        )
      end

      def webhook_type
        'fee.instant_created'
      end

      def object_type
        'fee'
      end
    end
  end
end
