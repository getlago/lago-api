# frozen_string_literal: true

module Api
  module V2
    module Plans
      # Lists, shows, replaces, merges and removes the entitlements of a catalog plan, and removes one of their privilege
      # values, with the v1 body, and the v2 response and errors.
      class EntitlementsController < Api::V2::BaseController
        include Api::EntitlementsErrors

        serializable_with ::V2::PlanEntitlementSerializer, root: :plan_entitlement, expand_on: []

        # Before the lookup, like the cursor of the paginated lists.
        before_action :reject_pagination!, only: %i[index show create update destroy destroy_privilege]
        before_action :find_catalog_plan

        # Bounded by the entitlement limit of a catalog plan: returned whole, without pagination.
        # The join drops the entitlements of a discarded feature, as v1 does.
        def index
          render_plan_entitlements(catalog_plan.entitlements.joins(:feature).includes(:catalog_plan, :feature, values: :privilege).newest_first)
        end

        def show
          entitlement = find_entitlement

          if entitlement
            render_plan_entitlement(entitlement)
          else
            not_found_error(resource: "feature")
          end
        end

        # Renders the removed entitlement with the values it had, which stay loaded after the discard, and its deleted_at.
        def destroy
          entitlement = find_entitlement
          return not_found_error(resource: "feature") unless entitlement

          result = ::Entitlement::PlanEntitlementDestroyService.call(entitlement:)

          if result.success?
            render_plan_entitlement(result.entitlement)
          else
            render_error_response(result)
          end
        end

        # Removes one privilege value and renders the entitlement with the values it keeps.
        def destroy_privilege
          entitlement = find_entitlement
          return not_found_error(resource: "feature") unless entitlement

          result = ::Entitlement::PlanEntitlementPrivilegeDestroyService.call(entitlement:, privilege_code: params[:privilege_code])

          if result.success?
            render_plan_entitlement(result.entitlement)
          else
            render_error_response(result)
          end
        end

        # Replaces: discards the features and values left out of the body.
        def create
          update_entitlements(partial: false)
        end

        # Merges: keeps the features and values left out of the body.
        def update
          update_entitlements(partial: true)
        end

        private

        attr_reader :catalog_plan

        def update_entitlements(partial:)
          permitted = params.slice(:entitlements).permit(entitlements: {})
          # An empty map is valid, and a replace with it discards every entitlement. A missing or non-map value is a 400.
          return missing_parameter_error(ActionController::ParameterMissing.new(:entitlements)) unless permitted.key?(:entitlements)

          result = ::Entitlement::PlanEntitlementsUpdateService.call(
            organization: current_organization,
            plan: catalog_plan,
            entitlements_params: permitted[:entitlements].to_h,
            partial:
          )

          if result.success?
            render_plan_entitlements(result.entitlements)
          else
            render_entitlements_error(result)
          end
        end

        # A partial unique index allows one kept entitlement per feature and catalog plan. The join
        # makes the entitlement of a discarded feature a 404, as v1 does.
        def find_entitlement
          catalog_plan.entitlements
            .joins(:feature)
            .preload(:catalog_plan, :feature, values: :privilege)
            .find_by(entitlement_features: {code: params[:code]})
        end

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
