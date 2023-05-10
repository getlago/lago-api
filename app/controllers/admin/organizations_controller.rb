# frozen_string_literal: true

module Admin
  class OrganizationsController < BaseController
    def update
      render(
            json: ::V1::OrganizationSerializer.new(
              current_organization,
              root_name: 'organization',
            ),
          )
    end

    private

    def current_organization
      pp params[:id]
      @current_organization ||= Organization.find_by(id: params[:id])
    end

    def input_params
      params.permit(:name)
    end
  end
end
