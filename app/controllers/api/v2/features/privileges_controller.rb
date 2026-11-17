# frozen_string_literal: true

module Api
  module V2
    module Features
      class PrivilegesController < Api::V2::BaseController
        serializable_with ::V2::Entitlement::PrivilegeSerializer, root: :privilege

        def create
          attributes = params.expect(privilege: [:code, :name, :value_type, select_options: []])

          result = ::Entitlement::PrivilegeCreateService.call(
            # The service answers not found for an unknown or discarded code.
            feature: current_organization.features.find_by(code: params[:feature_code]),
            params: attributes.to_h
          )

          if result.success?
            render_privilege(result.privilege)
          else
            render_error_response(result)
          end
        end

        private

        def resource_name
          "feature"
        end
      end
    end
  end
end
