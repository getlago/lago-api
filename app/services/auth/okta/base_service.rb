# frozen_string_literal: true

module Auth
  module Okta
    class BaseService < BaseService
      include Auth::SsoIntegrationChecks

      private

      def check_code
        raise ValidationError, "code_not_found" if code.blank?
      end

      def check_state
        raise ValidationError, "state_not_found" if state.blank?

        email = Rails.cache.read(state)
        raise ValidationError, "state_not_found" if email.blank?

        Rails.cache.delete(state)

        result.email = email
      end

      def check_okta_integration(email, organization_id: nil)
        okta_integration = ::Integrations::OktaIntegration.for_login(email:, organization_id:)

        raise ValidationError, "domain_not_configured" if okta_integration.blank?

        result.okta_integration = okta_integration
      end

      def sso_integration
        result.okta_integration
      end

      def sso_login_method
        Organizations::AuthenticationMethods::OKTA
      end

      def check_invite(email)
        invite = Invite.pending.find_by(token: invite_token)

        raise ValidationError, "invite_not_found" if invite.blank?
        raise ValidationError, "invite_email_mismatch" if invite.email != email

        result.invite = invite
      end

      def query_okta_access_token
        params = {
          client_id: result.okta_integration.client_id,
          client_secret: result.okta_integration.client_secret,
          grant_type: "authorization_code",
          code:,
          redirect_uri: "#{Rails.application.config.lago_front_url}/auth/okta/callback"
        }

        token_client = LagoHttpClient::Client.new("https://#{result.okta_integration.host}/oauth2/v1/token", block_private_addresses: true)
        response = token_client.post_url_encoded(params, {})
        result.okta_access_token = response["access_token"]
      end

      # NOTE: Okta casing is not guaranteed to match the typed email.
      def check_userinfo(email)
        userinfo_client = LagoHttpClient::Client.new("https://#{result.okta_integration.host}/oauth2/v1/userinfo", block_private_addresses: true)
        userinfo_headers = {"Authorization" => "Bearer #{result.okta_access_token}"}
        response = userinfo_client.get(headers: userinfo_headers)

        raise ValidationError, "okta_userinfo_error" unless response["email"]&.casecmp?(email)

        result.userinfo = response
      end
    end

    class ValidationError < StandardError; end
  end
end
