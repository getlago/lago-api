# frozen_string_literal: true

module Webhooks
  module AddOns
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::AddOnSerializer.new(
          object,
          root_name: "add_on"
        )
      end

      def webhook_type
        "add_on.deleted"
      end

      def object_type
        "add_on"
      end
    end
  end
end
