# frozen_string_literal: true

module Webhooks
  module Products
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::ProductSerializer.new(object, root_name: object_type)
      end

      def webhook_type
        "product.deleted"
      end

      def object_type
        "product"
      end
    end
  end
end
