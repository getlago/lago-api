# frozen_string_literal: true

module Admin
  class OrganizationsController < BaseController
    def update
      result = Admin::Organizations::UpdateService.call(
        organization:,
        params: update_params
      )

      return render_error_response(result) unless result.success?

      render(
        json: ::V1::OrganizationSerializer.new(
          result.organization,
          root_name: 'organization'
        )
      )
    end

    private

    def organization
      @organization ||= Organization.find_by(id: params[:id])
    end

    def update_params
      params.permit(:name)
    end
  end
end
