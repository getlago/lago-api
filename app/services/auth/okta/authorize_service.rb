# frozen_string_literal: true

require 'redis'

module Auth
  module Okta
    class AuthorizeService < BaseService
      def initialize(email:, invite_token: nil)
        @email = email
        @invite_token = invite_token
        initialize_state

        super
      end

      def call
        check_invite if invite_token.present?
        check_okta_integration

        params = {
          client_id: result.okta_integration.client_id,
          response_type: 'code',
          response_mode: 'query',
          scope: 'openid profile email',
          redirect_uri: "#{ENV['LAGO_FRONT_URL']}/auth/okta/callback",
          state:,
        }
        result.url = URI::HTTPS.build(
          host: "#{result.okta_integration.organization_name.downcase}.okta.com",
          path: '/oauth2/default/v1/authorize',
          query: params.to_query,
        ).to_s

        result
      rescue ValidationError => e
        result.single_validation_failure!(error_code: e.message)
        result
      end

      private

      attr_reader :email, :invite_token

      def check_invite
        invite = Invite.pending.find_by(token: invite_token)

        raise ValidationError, 'invite_not_found' if invite.blank?
        raise ValidationError, 'invite_email_mistmatch' if invite.email != email

        result.invite = invite
      end

      def check_okta_integration
        email_domain = email.split('@').last
        okta_integration = ::Integrations::OktaIntegration
          .where('settings->>\'domain\' IS NOT NULL')
          .where('settings->>\'domain\' = ?', email_domain)
          .first

        raise ValidationError, 'domain_not_configured' if okta_integration.blank?

        result.okta_integration = okta_integration
      end

      def initialize_state
        Rails.cache.write(state, email, expires_in: 90.seconds)
      end

      def state
        @state ||= SecureRandom.uuid
      end

      class ValidationError < StandardError; end
    end
  end
end
