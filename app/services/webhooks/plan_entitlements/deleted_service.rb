# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::PlanEntitlementSerializer.new(object, root_name: "plan_entitlement", values: values_before)
      end

      # The values are discarded with the entitlement, so the sender passes the ones it had before the delete.
      def values_before
        options[:values]&.map { it.to_h.symbolize_keys }
      end

      def webhook_type
        "plan_entitlement.deleted"
      end

      def object_type
        "plan_entitlement"
      end
    end
  end
end
