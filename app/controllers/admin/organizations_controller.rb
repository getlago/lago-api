# frozen_string_literal: true

module Admin
  class OrganizationsController < BaseController
    def create
      result = Admin::Organizations::CreateService.call(params: create_params)

      return render_error_response(result) unless result.success?

      render(
        json: ::V1::OrganizationSerializer.new(
          result.organization,
          root_name: "organization"
        ),
        status: :created
      )
    end

    def update
      result = Admin::Organizations::UpdateService.call(
        organization:,
        params: update_params
      )

      return render_error_response(result) unless result.success?

      render(
        json: ::V1::OrganizationSerializer.new(
          result.organization,
          root_name: "organization"
        )
      )
    end

    private

    def organization
      @organization ||= Organization.find_by(id: params[:id])
    end

    def create_params
      params.permit(:name, :email, :country, :address_line1, :address_line2, :state, :zipcode, :city, :timezone, :premium_features, :billing_configuration)
    end

    def update_params
      params.permit(:name)
    end
  end
end
