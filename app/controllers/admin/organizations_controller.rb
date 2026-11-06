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
        json: ::Admin::OrganizationSerializer.new(
          result.organization,
          root_name: "organization"
        )
      )
    end

    def create
      result = ::Organizations::CreateWithInviteService.call(
        name: create_params[:name],
        owner_email: create_params[:email],
        document_numbering: "per_customer",
        premium_integrations: create_params[:premium_integrations] || [],
        self_serve: self_serve_param
      )

      if result.success?
        render json: {
          organization: ::Admin::OrganizationSerializer.new(result.organization).serialize,
          sandbox_organization: result.sandbox_organization && ::Admin::OrganizationSerializer.new(result.sandbox_organization).serialize,
          invite_url: result.invite_url
        }, status: :created
      else
        render_error_response(result)
      end
    end

    private

    def organization
      @organization ||= Organization.find_by(id: params[:id])
    end

    def update_params
      params.permit(:name, premium_integrations: [])
    end

    def create_params
      params.permit(:name, :email, :self_serve, premium_integrations: [])
    end

    # Strict: ActiveModel's boolean cast would read "no" as true. Anything else reaches the service, which refuses it.
    def self_serve_param
      value = create_params[:self_serve]
      case value
      when nil, false, "false" then false
      when true, "true" then true
      else value
      end
    end
  end
end
