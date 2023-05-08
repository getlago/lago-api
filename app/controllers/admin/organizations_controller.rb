# frozen_string_literal: true

module Admin
  class OrganizationsController < BaseController
    def update
      result = Organizations::UpdateService.call(organization: current_organization, params: input_params)

      
    end

    private

    def current_organization
      @current_organization ||= Organization.find_by(params[:id])
    end

    def input_params
      params.require(:organization).permit(:name)
    end
  end
end
