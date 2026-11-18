# frozen_string_literal: true

module Auth
  module Okta
    class LoginService < BaseService
      Result = BaseResult[:email, :okta_integration, :okta_access_token, :userinfo, :user, :token]

      def initialize(code:, state:)
        @code = code
        @state = state

        super
      end

      def call
        check_state
        check_code
        check_okta_integration(result.email)

        query_okta_access_token
        check_userinfo(result.email)

        return login_method_not_authorized_failure unless integration_organization_allows_login_method?
        return result.forbidden_failure!(code: "sandbox_managed_by_production") if sandbox_refuses_new_member?

        find_or_create_user
        return login_method_not_authorized_failure unless user_trusted_by_integration?(result.user)

        find_or_create_membership

        UserDevices::RegisterService.call!(user: result.user)
        generate_token
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
        result
      rescue BaseLockService::FailedToAcquireLock
        result.lock_acquisition_failure!(message: "email lock not acquired")
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e)
      end

      private

      attr_reader :code, :state

      def generate_token
        result.token = Utils::AuthToken.encode(
          user: result.user,
          login_method: Organizations::AuthenticationMethods::OKTA,
          **sso_token_claims
        )
        result
      rescue => e
        result.service_failure!(code: "token_encoding_error", message: e.message)
      end

      # NOTE: Okta compares the typed email case-insensitively (see #check_userinfo), so the Lago
      #       user is found the same way, or another casing creates a second user. An exact match
      #       wins, then the oldest case-insensitive match.
      def find_or_create_user
        result.user = find_user || create_user
      end

      def find_user
        User.lookup_by_email(result.email)
      end

      # Under the email lock, as every user creation, which also ends the address's open self-serve signups.
      def create_user
        user = User.new(email: result.email, password: SecureRandom.hex(16)) # bcrypt runs here, outside the lock

        Users::EmailLockService.call(email: result.email) do
          existing_user = find_user
          next existing_user if existing_user

          user.save!
          Signups::CloseAttemptsService.call!(normalized_email: PendingSignup.normalize_email(result.email))
          user
        end.value
      end
    end
  end
end
