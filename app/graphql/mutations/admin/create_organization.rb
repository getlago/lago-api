# frozen_string_literal: true

module Mutations
  module Admin
    class CreateOrganization < BaseMutation
      include AuthenticableAdminUser

      graphql_name "AdminCreateOrganization"
      description "Create a new organization with pre-configured features"

      argument :name, String, required: true
      argument :owner_email, String, required: true
      argument :timezone, String, required: false
      argument :premium_integrations, [String], required: false
      argument :feature_flags, [String], required: false
      argument :reason, String, required: true

      type Types::Admin::OrganizationType

      def resolve(**args)
        result = ::Admin::CreateOrganizationService.new(
          actor: current_user,
          name: args[:name],
          owner_email: args[:owner_email],
          timezone: args[:timezone],
          premium_integrations: args[:premium_integrations],
          feature_flags: args[:feature_flags],
          reason: args[:reason]
        ).call

        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
