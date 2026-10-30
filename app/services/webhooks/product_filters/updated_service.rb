# frozen_string_literal: true

module Webhooks
  module ProductFilters
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ProductFilterSerializer.new(object, root_name: object_type)
      end

      def webhook_type
        "product_filter.updated"
      end

      def object_type
        "product_filter"
      end
    end
  end
end
