# frozen_string_literal: true

module Api
  module V2
    module Features
      class PrivilegesController < Api::V2::BaseController
        serializable_with ::V2::Entitlement::PrivilegeSerializer, root: :privilege

        # Bounded by their feature and returned whole: every pagination param is refused, before
        # the lookup like the cursor of the paginated lists.
        before_action :reject_pagination!, only: :index

        def index
          feature = current_organization.features.find_by(code: params[:feature_code])

          if feature
            render_privileges(feature.ordered_privileges)
          else
            not_found_error(resource: "feature")
          end
        end

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
