# frozen_string_literal: true

module Mutations
  module Admin
    class LoginUser < BaseMutation
      graphql_name "AdminLoginUser"
      description "Opens a staff-only session against the admin_users table"

      argument :email, String, required: true
      argument :password, String, required: true

      type Types::Admin::LoginPayloadType

      def resolve(email:, password:)
        result = ::AdminUsers::LoginService.call(email: email, password: password)
        return result_error(result) unless result.success?

        admin_user = result.admin_user

        {
          token: result.token,
          admin_user: admin_user,
          role: admin_user.role,
          allowed_integrations: admin_user.allowed_integrations,
          reason_categories: ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES
        }
      end
    end
  end
end
