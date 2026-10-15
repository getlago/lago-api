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

        find_or_create_user
        return login_method_not_authorized_failure unless user_belongs_to_integration_organization?

        find_or_create_membership

        unless result.user.active_organizations.pluck(:authentication_methods).flatten.uniq.include?(Organizations::AuthenticationMethods::ENTRA_ID)
          return login_method_not_authorized_failure
        end

        UserDevices::RegisterService.call!(user: result.user)
        generate_token
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
        result
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
        user = User.find_by(email: result.email) ||
          User.where("LOWER(email) = ?", result.email.downcase).order(:created_at).first

        if user.nil?
          user = User.new(email: result.email, password: SecureRandom.hex(16))
          user.save!
        end

        result.user = user
      end

      # NOTE: The identity provider of an integration is chosen by its organization, so it only
      #       vouches for that organization's users. An existing user joins another one through an invite.
      def user_belongs_to_integration_organization?
        result.user.previously_new_record? ||
          result.user.memberships.active.exists?(organization_id: result.entra_id_integration.organization_id)
      end

      def login_method_not_authorized_failure
        result.single_validation_failure!(
          error_code: "login_method_not_authorized",
          field: Organizations::AuthenticationMethods::ENTRA_ID
        )
      end

      def find_or_create_membership
        result.user.memberships.find_or_create_by(organization_id: result.entra_id_integration.organization_id)
      end
    end
  end
end
