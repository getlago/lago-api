# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    # SendWebhookJob loads the entitlement with nothing preloaded, and its render reads the privilege of every
    # value, so the associations are loaded in one query each before the render.
    module PlanEntitlementPayload
      private

      def object_serializer
        ActiveRecord::Associations::Preloader.new(records: [object], associations: preloaded_associations).call
        ::V2::PlanEntitlementSerializer.new(object, root_name: "plan_entitlement", **serializer_options)
      end

      def preloaded_associations
        [:catalog_plan, :feature, {values: :privilege}]
      end

      def serializer_options
        {}
      end

      def object_type
        "plan_entitlement"
      end
    end
  end
end
