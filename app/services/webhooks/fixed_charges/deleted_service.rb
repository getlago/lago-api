# frozen_string_literal: true

module Webhooks
  module FixedCharges
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::FixedChargeSerializer.new(object, root_name: object_type, includes: %i[taxes])
      end

      def webhook_type
        "fixed_charge.deleted"
      end

      def object_type
        "fixed_charge"
      end
    end
  end
end
