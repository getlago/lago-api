# frozen_string_literal: true

module Api
  module V2
    module Plans
      # Replaces the entitlements of a catalog plan, with the v1 body and response and the v2 errors.
      # The other entitlement routes of a plan still reach the v1 controller.
      class EntitlementsController < Api::V2::BaseController
        serializable_with ::V1::Entitlement::PlanEntitlementSerializer, root: :entitlement, expand_on: []

        before_action :reject_pagination!
        before_action :find_catalog_plan

        def create
          # Not `params.require`, which refuses an empty map: an empty map discards every entitlement.
          return missing_parameter_error(ActionController::ParameterMissing.new(:entitlements)) unless params.key?(:entitlements)

          invalid_field = invalid_entitlements_field
          return invalid_entitlements_error(invalid_field) if invalid_field

          result = ::Entitlement::PlanEntitlementsUpdateService.call(
            organization: current_organization,
            plan: catalog_plan,
            entitlements_params: params[:entitlements].permit!.to_h,
            partial: false
          )

          if result.success?
            render_entitlements(result.entitlements)
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

        # The first path of the body that is not a map of feature codes to maps of privilege codes to scalars.
        def invalid_entitlements_field
          entitlements = params[:entitlements]
          return "entitlements" unless entitlements.is_a?(ActionController::Parameters)

          entitlements.each_pair.lazy.filter_map { |feature_code, values| invalid_feature_field(feature_code, values) }.first
        end

        def invalid_feature_field(feature_code, privilege_values)
          if privilege_values.is_a?(ActionController::Parameters)
            privilege_code, _value = privilege_values.each_pair.find { |_code, value| !scalar?(value) }
            "entitlements.#{feature_code}.#{privilege_code}" if privilege_code
          else
            "entitlements.#{feature_code}"
          end
        end

        def scalar?(value)
          value.nil? || value == true || value == false || value.is_a?(String) || value.is_a?(Numeric)
        end

        def invalid_entitlements_error(field)
          invalid_request_error(code: "value_is_invalid", error_details: {field => {reason: "value_is_invalid"}})
        end

        # The service renders its validation failures on the path of the entry for native v2. An unknown
        # feature or privilege of the body, a 404 on v1, is a 422 on entitlements.<feature>[.<privilege>].
        def render_entitlements_error(result)
          field = result.failed_field
          error = result.error
          return render_error_response(result) unless field && error.is_a?(BaseService::NotFoundFailure)

          validation_errors(errors: {field => ["resource_not_found"]}, meta: {field => {resource: error.resource}})
        end

        def resource_name
          "plan"
        end
      end
    end
  end
end
