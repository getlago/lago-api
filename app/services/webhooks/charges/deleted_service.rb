# frozen_string_literal: true

module Webhooks
  module Charges
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::ChargeSerializer.new(object, root_name: object_type, includes: %i[taxes])
      end

      def webhook_type
        "charge.deleted"
      end

      def object_type
        "charge"
      end
    end
  end
end
