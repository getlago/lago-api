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

        return result unless result.success?

        check_okta_integration

        return result unless result.success?

        query_okta_access_token
        check_userinfo

        return result unless result.success?

        find_or_create_user
        find_or_create_membership

        UsersService.new.new_token(result.user)
      end

      private

      attr_reader :code, :state

      def check_state
        redis_config = { url: ENV['REDIS_URL'] }
        redis_config.merge({ password: ENV['REDIS_PASSWORD'] }) if ENV['REDIS_PASSWORD'].present?
        redis_client = ::Redis.new(url: ENV['REDIS_URL'])

        email = redis_client.get(state)
        return result.single_validation_failure!(error_code: 'state_not_found') if email.blank?

        redis_client.del(state)

        result.email = email
      end

      def check_integration
        okta_integration = ::Integrations::OktaIntegration
          .where('settings->>\'domain\' IS NOT NULL')
          .where('settings->>\'domain\' = ?', result.email.split('@').last)
          .first

        return result.single_validation_failure!(error_code: 'domain_not_configured') if okta_integration.blank?

        result.okta_integration = okta_integration
      end

      def query_okta_access_token
        params = {
          client_id: result.okta_integration.client_id,
          client_secret: result.okta_integration.client_secret,
          grant_type: 'authorization_code',
          code:,
          redirect_uri: "#{ENV['LAGO_FRONT_URL']}/auth/okta/callback",
        }

        token_client = LagoHttpClient.new("https://#{result.okta_integration.organization_name.downcase}.okta.com/oauth2/default/v1/token")
        response = token_client.post(params, {})
        result.okta_access_token = response['access_token']
      end

      def check_userinfo
        userinfo_client = LagoHttpClient.new("https://#{result.okta_integration.organization_name.downcase}.okta.com/oauth2/default/v1/userinfo")
        userinfo_headers = { 'Authorization' => "Bearer #{okta_access_token}" }
        response = userinfo_client.get(userinfo_headers)

        return result.single_validation_failure!(error_code: 'okta_userinfo_error') if response['email'] != result.email

        result.userinfo = response
      end

      def find_or_create_user
        user = User.find_or_initialize_by(email: result.email)

        if user.new_record?
          user.password = SecureRandom.hex(16)
          user.save!
        end

        result.user = user
      end

      def find_or_create_membership
        membership = user.memberships.find_or_initialize_by(organization_id: result.okta_integration.organization_id)

        membership.save! if membership.new_record?

        result.membership = membership
      end
    end
  end
end
