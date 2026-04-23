# frozen_string_literal: true

module Mutations
  module Admin
    class LoginUser < BaseMutation
      graphql_name "AdminLoginUser"
      description "Opens a staff-only session. Same credentials as the regular Lago login, but only users on the staff allowlist are allowed through."

      argument :email, String, required: true
      argument :password, String, required: true

      type Types::Admin::LoginPayloadType

      def resolve(email:, password:)
        role = AuthenticableStaffUser.role_for(email)
        return forbidden_staff_error if role.blank?

        result = UsersService.new.login(email, password)
        return result_error(result) unless result.success?

        # Re-check role by canonical user email (in case of casing / sanitization differences).
        role = AuthenticableStaffUser.role_for(result.user.email)
        return forbidden_staff_error if role.blank?

        allowed = ::Admin::PremiumIntegrations::ToggleService::ROLE_ALLOWED_INTEGRATIONS[role]
        allowed_list = (allowed == :all) ? ::Organization::PREMIUM_INTEGRATIONS : allowed

        {
          token: result.token,
          user: result.user,
          role: role.to_s,
          allowed_integrations: allowed_list,
          reason_categories: ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES
        }
      end

      private

      def forbidden_staff_error
        GraphQL::ExecutionError.new(
          "not_staff_member",
          extensions: {status: :forbidden, code: "not_staff_member"}
        )
      end
    end
  end
end
