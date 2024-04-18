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
        result = check_state

        return result unless result.success?

        result = check_okta_integration(result.email)

        return result unless result.success?

        params = {
          client_id: result.okta_integration.client_id,
          client_secret: result.okta_integration.client_secret,
          grant_type: 'authorization_code',
          code:,
          redirect_uri: "#{ENV['LAGO_FRONT_URL']}/auth/okta/callback",
        }

        # TODO: call the Okta API to exchange the code for a token
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
        result
      end

      def check_integration(email)
        okta_integration = ::Integrations::OktaIntegration
          .where('settings->>\'domain\' IS NOT NULL')
          .where('settings->>\'domain\' = ?', email.split('@').last)
          .first

        return result.single_validation_failure!(error_code: 'domain_not_configured') if okta_integration.blank?

        result.okta_integration = okta_integration
        result
      end
    end
  end
end
