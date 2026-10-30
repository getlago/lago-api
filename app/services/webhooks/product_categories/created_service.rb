# frozen_string_literal: true

module Webhooks
  module ProductCategories
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ProductCategorySerializer.new(object, root_name: object_type, webhook: true)
      end

      def webhook_type
        "product_category.created"
      end

      def object_type
        "product_category"
      end
    end
  end
end
