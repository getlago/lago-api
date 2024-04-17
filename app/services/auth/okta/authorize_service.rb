# frozen_string_literal: true

require 'redis'

module Auth
  module Okta
    class AuthorizeService < BaseService
      def initialize(email:)
        @email = email
        initialize_state

        super
      end

      def call
        email_domain = email.split('@').last
        okta_integration = ::Integrations::OktaIntegration
          .where('settings->>\'domain\' IS NOT NULL')
          .where('settings->>\'domain\' = ?', email_domain)
          .first

        return result.single_validation_failure!(error_code: 'domain_not_configured') if okta_integration.blank?

        params = {
          client_id: okta_integration.client_id,
          response_type: 'code',
          response_mode: 'query',
          scope: 'openid profile email',
          redirect_uri: "#{ENV['LAGO_FRONT_URL']}/auth/okta/callback",
          state:,
        }
        result.url = URI::HTTPS.build(
          host: "#{okta_integration.organization_name.downcase}.okta.com",
          path: '/oauth2/default/v1/authorize',
          query: params.to_query,
        ).to_s

        result
      end

      private

      attr_reader :email

      def initialize_state
        redis_config = { url: ENV['REDIS_URL'] }
        redis_config.merge({ password: ENV['REDIS_PASSWORD'] }) if ENV['REDIS_PASSWORD'].present?
        redis_client = ::Redis.new(url: ENV['REDIS_URL'])

        redis_client.set(state, email)
      end

      def state
        @state ||= SecureRandom.uuid
      end
    end
  end
end
