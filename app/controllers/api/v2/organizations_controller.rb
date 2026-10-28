# frozen_string_literal: true

module Api
  module V2
    class OrganizationsController < Api::V2::BaseController
      serializable_with ::V2::OrganizationSerializer, expand_on: []

      def show
        render_organization(current_organization)
      end

      def update
        input = input_params
        validation = ::Organizations::ValidateApiInputService.call(params: input)
        return render_error_response(validation) unless validation.success?

        result = ::Organizations::UpdateService.call(organization: current_organization, params: input)

        if result.success?
          render_organization(result.organization)
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        input = params.require(:organization)
        unless input.is_a?(ActionController::Parameters)
          raise ActionController::ParameterMissing, :organization
        end

        input.permit(:email, :slug)
      end

      def resource_name
        "organization"
      end
    end
  end
end
