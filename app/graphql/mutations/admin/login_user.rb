# frozen_string_literal: true

module Mutations
  module Admin
    class LoginUser < BaseMutation
      graphql_name "AdminLoginUser"
      description "Opens a staff-only session. Credentials are hardcoded in app/support/admin_staff_credentials.rb (hackathon)."

      argument :email, String, required: true
      argument :password, String, required: true

      type Types::Admin::LoginPayloadType

      def resolve(email:, password:)
        staff = AdminStaffCredentials.authenticate(email, password)
        return incorrect_login_error if staff.nil?

        token = ::Auth::TokenService.encode(user_id: staff.email, admin: true)

        allowed = ::Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS[staff.role]
        allowed_list = (allowed == :all) ? ::Organization::PREMIUM_INTEGRATIONS : Array(allowed)

        {
          token: token,
          admin_user: staff,
          role: staff.role.to_s,
          allowed_integrations: allowed_list,
          reason_categories: ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES
        }
      end

      private

      def incorrect_login_error
        GraphQL::ExecutionError.new(
          "incorrect_login_or_password",
          extensions: {status: :unprocessable_entity, code: "unprocessable_entity"}
        )
      end
    end
  end
end
