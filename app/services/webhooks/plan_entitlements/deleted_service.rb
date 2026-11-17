# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    class DeletedService < Webhooks::BaseService
      include PlanEntitlementPayload

      private

      # The values are discarded with the entitlement, so they are not loaded: the sender passes the ones it
      # had before the delete.
      def preloaded_associations
        [:catalog_plan, :feature]
      end

      def serializer_options
        {values: options[:values]&.map { it.to_h.symbolize_keys }}
      end

      def webhook_type
        "plan_entitlement.deleted"
      end
    end
  end
end
