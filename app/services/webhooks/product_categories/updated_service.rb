# frozen_string_literal: true

module Webhooks
  module ProductCategories
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ProductCategorySerializer.new(object, root_name: object_type)
      end

      def webhook_type
        "product_category.updated"
      end

      def object_type
        "product_category"
      end
    end
  end
end
