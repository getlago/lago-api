# frozen_string_literal: true

module Webhooks
  module PlanEntitlements
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::PlanEntitlementSerializer.new(object, root_name: "plan_entitlement")
      end

      def webhook_type
        "plan_entitlement.created"
      end

      def object_type
        "plan_entitlement"
      end
    end
  end
end
