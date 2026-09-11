# frozen_string_literal: true

module Webhooks
  module Plans
    class DeletedService < Webhooks::BaseService
      private

      def object_serializer
        # A catalog plan is a plan to the end user: same webhook type, its own
        # (leaner) payload.
        return ::V2::CatalogPlanSerializer.new(object, root_name: "plan") if object.is_a?(CatalogPlan)

        ::V1::PlanSerializer.new(
          object,
          root_name: "plan",
          includes: %i[charges usage_thresholds taxes minimum_commitment]
        )
      end

      def webhook_type
        "plan.deleted"
      end

      def object_type
        "plan"
      end
    end
  end
end
