# frozen_string_literal: true

module Resolvers
  module Admin
    class CurrentStaffResolver < Resolvers::BaseResolver
      include AuthenticableStaffUser

      description "Returns the role and allowed integrations for the current admin user"

      type Types::Admin::CurrentStaffType, null: false

      StaffInfo = Struct.new(:email, :role, :allowed_integrations, :reason_categories, keyword_init: true)

      def resolve
        admin = current_admin_user

        StaffInfo.new(
          email: admin.email,
          role: admin.role,
          allowed_integrations: admin.allowed_integrations,
          reason_categories: ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES
        )
      end
    end
  end
end
