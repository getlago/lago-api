# frozen_string_literal: true

module Auth
  module Okta
    class AcceptInviteService < BaseService
      def initialize(invite_token:, code:, state:)
        @invite_token = invite_token
        @code = code
        @state = state

        super
      end

      def call
        check_state
        check_okta_integration(result.email)
        check_invite(result.email)
        query_okta_access_token
        check_userinfo(result.email)

        Invites::AcceptService.new.call(
          invite: result.invite,
          email: result.email,
          token: invite_token,
          password: SecureRandom.hex
        )
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
      rescue LagoHttpClient::HttpError
        result.single_validation_failure!(error_code: 'okta_request_error')
        result
      end

      private

      attr_reader :invite_token, :code, :state
    end
  end
end
