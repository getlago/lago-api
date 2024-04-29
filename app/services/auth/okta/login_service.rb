# frozen_string_literal: true

module Auth
  module Okta
    class LoginService < BaseService
      def initialize(code:, state:)
        @code = code
        @state = state

        super
      end

      def call
        check_state
        check_okta_integration(result.email)

        query_okta_access_token
        check_userinfo(result.email)

        find_or_create_user
        find_or_create_membership

        UsersService.new.new_token(result.user)
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
        result
      rescue LagoHttpClient::HttpError
        result.single_validation_failure!(error_code: 'okta_request_error')
        result
      end

      private

      attr_reader :code, :state

      def find_or_create_user
        user = User.find_or_initialize_by(email: result.email)

        if user.new_record?
          user.password = SecureRandom.hex(16)
          user.save!
        end

        result.user = user
      end

      def find_or_create_membership
        result.user.memberships.find_or_create_by(organization_id: result.okta_integration.organization_id)
      end
    end
  end
end
