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
          root_name: "organization"
        )
      )
    end

    def create
      result = ::Organizations::CreateService
        .call(name: create_params[:name], document_numbering: "per_organization")

      return render_error_response(result) unless result.success?

      organization = result.organization

      invite_result = ::Invites::CreateService.call(
        current_organization: organization,
        email: create_params[:email],
        role: :admin
      )

      return render_error_response(invite_result) unless invite_result.success?

      render json: {
        organization: ::V1::OrganizationSerializer.new(organization).serialize,
        invite_url: invite_result.invite_url
      }, status: :created
    end

    private

    def organization
      @organization ||= Organization.find_by(id: params[:id])
    end

    def update_params
      params.expect(:name)
    end

    def create_params
      params.expect(:name, :email)
    end
  end
end
