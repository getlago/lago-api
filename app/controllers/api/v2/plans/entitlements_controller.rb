# frozen_string_literal: true

module Api
  module V2
    module Plans
      # Replaces the entitlements of a catalog plan, with the v1 body, and the v2 response and errors.
      # The other entitlement routes of a plan still reach the v1 controller.
      class EntitlementsController < Api::V2::BaseController
        include Api::EntitlementsErrors

        serializable_with ::V2::PlanEntitlementSerializer, root: :plan_entitlement, expand_on: []

        # Before the lookup, like the cursor of the paginated lists.
        before_action :reject_pagination!, only: :create
        before_action :find_catalog_plan

        def create
          permitted = params.slice(:entitlements).permit(entitlements: {})
          # An empty map is valid: it discards every entitlement. A missing or non-map value is a 400.
          return missing_parameter_error(ActionController::ParameterMissing.new(:entitlements)) unless permitted.key?(:entitlements)

          result = ::Entitlement::PlanEntitlementsUpdateService.call(
            organization: current_organization,
            plan: catalog_plan,
            entitlements_params: permitted[:entitlements].to_h,
            partial: false
          )

          if result.success?
            render_plan_entitlements(result.entitlements)
          else
            render_entitlements_error(result)
          end
        end

        private

        attr_reader :catalog_plan

        def find_catalog_plan
          @catalog_plan = current_organization.catalog_plans.find_by(code: params[:plan_code])
          not_found_error(resource: "plan") unless @catalog_plan
        end

        def resource_name
          "plan"
        end
      end
    end
  end
end
