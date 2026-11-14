# frozen_string_literal: true

module V2
  module CatalogPlans
    # The body of plan.entitlements_updated: the plan as the other plan webhooks send it, and its
    # entitlements. Not an expansion of the plan, so that the other plan webhooks stay unchanged.
    class EntitlementsUpdatedSerializer < ModelSerializer
      def serialize
        plan.merge(entitlements:)
      end

      private

      def plan
        ::V2::CatalogPlanSerializer.new(model, webhook: true, includes: %i[counts]).serialize
      end

      # The kept ones, oldest first, preloaded so that the number of queries does not grow with them.
      def entitlements
        model.entitlements
          .includes(:catalog_plan, :feature, values: :privilege)
          .oldest_first
          .map { ::V2::PlanEntitlementSerializer.new(it).serialize }
      end
    end
  end
end
