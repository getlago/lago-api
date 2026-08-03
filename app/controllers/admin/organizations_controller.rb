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
      return render_validation_error(errors: {reason: ["value_is_mandatory"]}) if create_params[:reason].blank?
      return render_validation_error(errors: {actor_email: ["value_is_mandatory"]}) if create_params[:actor_email].blank?

      actor = User.find_by(email: create_params[:actor_email])
      return render_validation_error(errors: {actor_email: ["value_is_invalid"]}) unless actor

      result = ::Admin::CreateOrganizationService.call(
        actor:,
        name: create_params[:name],
        owner_email: create_params[:email],
        reason: create_params[:reason],
        timezone: create_params[:timezone],
        premium_integrations: create_params[:premium_integrations],
        feature_flags: create_params[:feature_flags]
      )

      return render_error_response(result) unless result.success?

      render json: {
        organization: ::Admin::OrganizationSerializer.new(result.organization).serialize,
        invite_url: result.invite_url
      }, status: :created
    end

    private

    def render_validation_error(errors:)
      render_error_response(BaseResult.new.validation_failure!(errors:))
    end

    def organization
      @organization ||= Organization.find_by(id: params[:id])
    end

    def update_params
      params.permit(:name, premium_integrations: [])
    end

    def create_params
      params.permit(
        :name,
        :email,
        :actor_email,
        :reason,
        :timezone,
        premium_integrations: [],
        feature_flags: []
      )
    end
  end
end
