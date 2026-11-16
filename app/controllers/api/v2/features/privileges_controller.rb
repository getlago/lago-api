# frozen_string_literal: true

module Api
  module V2
    module Features
      class PrivilegesController < Api::V2::BaseController
        serializable_with ::V2::Entitlement::PrivilegeSerializer, root: :privilege

        def create
          result = ::Entitlement::PrivilegeCreateService.call(
            # The service answers not found for an unknown or discarded code.
            feature: current_organization.features.find_by(code: params[:feature_code]),
            params: input_params
          )

          if result.success?
            render_privilege(result.privilege)
          else
            render_error_response(result)
          end
        end

        private

        def input_params
          raw_input = params.require(:privilege)
          raise ActionController::ParameterMissing, :privilege unless raw_input.is_a?(ActionController::Parameters)

          # Passed raw: permit would silently drop an array or an object, which the service refuses.
          raw_input.to_unsafe_h.slice(:code, :name, :value_type, :select_options)
        end

        def resource_name
          "feature"
        end
      end
    end
  end
end
