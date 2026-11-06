# frozen_string_literal: true

module Auth
  module EntraId
    class LoginService < BaseService
      Result = BaseResult[:email, :entra_id_integration, :entra_id_access_token, :userinfo, :user, :token]

      def initialize(code:, state:)
        @code = code
        @state = state

        super
      end

      def call
        check_state
        check_code
        check_entra_id_integration(result.email)

        query_entra_id_access_token
        check_userinfo(result.email)

        return login_method_not_authorized_failure unless integration_organization_allows_login_method?

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
          login_method: Organizations::AuthenticationMethods::ENTRA_ID,
          **sso_token_claims
        )
        result
      rescue => e
        result.service_failure!(code: "token_encoding_error", message: e.message)
      end

      # NOTE: Entra ID compares the typed email case-insensitively (see #check_userinfo), so
      #       the Lago user must be found the same way. Otherwise a casing that differs from the
      #       invited address creates a second user with no role. An exact match wins, then the
      #       oldest case-insensitive match.
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

      # A membership of any status is kept as is, so a revoked member is not added back.
      def find_or_create_membership
        organization = result.entra_id_integration.organization
        return if result.user.memberships.exists?(organization_id: organization.id)

        ActiveRecord::Base.transaction do
          Organizations::SandboxLockService.call!(organization:)
          membership = result.user.memberships.find_or_create_by!(organization_id: organization.id)
          next unless membership.previously_new_record?

          Memberships::SyncSandboxService.call!(organization:, user: result.user, actor: result.user)
        end
      end
    end
  end
end
