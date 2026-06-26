# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Webhooks
  module Integrations
    class CustomerCreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::CustomerSerializer.new(
          object,
          root_name: object_type,
          includes: %i[integration_customers]
        )
      end

      def object_type
        "customer"
      end
    end
  end
end
