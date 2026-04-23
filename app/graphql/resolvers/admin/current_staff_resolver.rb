# frozen_string_literal: true

module Resolvers
  module Admin
    class CurrentStaffResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Returns the staff role and allowed integrations for the current user"

      type Types::Admin::CurrentStaffType, null: false

      StaffInfo = Struct.new(:email, :role, :allowed_integrations, :reason_categories, keyword_init: true)

      def resolve
        email = context[:current_user].email
        role = staff_role_for(email)
        allowed = ::Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS[role]
        allowed_list = (allowed == :all) ? ::Organization::PREMIUM_INTEGRATIONS : allowed

        StaffInfo.new(
          email: email,
          role: role.to_s,
          allowed_integrations: allowed_list,
          reason_categories: ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES
        )
      end
    end
  end
end
