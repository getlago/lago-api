# frozen_string_literal: true

module Auth
  module Okta
    class AcceptInviteService < BaseService
      Result = BaseResult[:email, :okta_integration, :invite, :okta_access_token, :userinfo]

      def initialize(invite_token:, code:, state:)
        @invite_token = invite_token
        @code = code
        @state = state

        super
      end

      def call
        check_state
        check_code
        check_okta_integration(result.email)
        check_invite(result.email)

        raise ValidationError, "existing_user_must_authenticate" if existing_user_outside_organization?

        query_okta_access_token
        check_userinfo(result.email)

        Invites::AcceptService.new.call(
          invite: result.invite,
          email: result.email,
          token: invite_token,
          password: SecureRandom.hex,
          login_method: Organizations::AuthenticationMethods::OKTA
        )
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
      rescue LagoHttpClient::HttpError
        result.single_validation_failure!(error_code: "okta_request_error")
        result
      end

      private

      attr_reader :invite_token, :code, :state

      def existing_user_outside_organization?
        user = User.find_by(email: result.email)
        return false if user.nil?

        !user.memberships.active.exists?(organization_id: result.invite.organization_id)
      end
    end
  end
end
