# frozen_string_literal: true

module Mutations
  module Admin
    class TogglePremiumIntegration < BaseMutation
      include AuthenticableStaffUser

      graphql_name "AdminTogglePremiumIntegration"
      description "Enable or disable a premium integration on an organization (Lago staff only)"

      argument :organization_id, ID, required: true
      argument :integration, String, required: true
      argument :enabled, Boolean, required: true
      argument :reason, String, required: true
      argument :reason_category, Types::Admin::ReasonCategoryEnum, required: true

      type Types::Admin::OrganizationType

      def resolve(organization_id:, integration:, enabled:, reason:, reason_category:)
        organization = ::Organization.find_by(id: organization_id)
        staff_role = staff_role_for(context[:current_user]&.email)

        result = ::Admin::PremiumIntegrations::ToggleService.call(
          organization: organization,
          integration: integration,
          enabled: enabled,
          reason: reason,
          reason_category: reason_category,
          user: context[:current_user],
          staff_role: staff_role
        )

        result.success? ? result.organization : result_error(result)
      end
    end
  end
end
