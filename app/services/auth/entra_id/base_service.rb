# frozen_string_literal: true

module Auth
  module EntraId
    class BaseService < BaseService
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

      def check_entra_id_integration(email)
        email_domain = email.split("@").last
        entra_id_integration = ::Integrations::EntraIdIntegration
          .where("settings->>'domain' IS NOT NULL")
          .where("settings->>'domain' = ?", email_domain)
          .first

        raise ValidationError, "domain_not_configured" if entra_id_integration.blank?

        result.entra_id_integration = entra_id_integration
      end

      def check_invite(email)
        invite = Invite.pending.find_by(token: invite_token)

        raise ValidationError, "invite_not_found" if invite.blank?
        raise ValidationError, "invite_email_mismatch" if invite.email != email

        result.invite = invite
      end

      def query_entra_id_access_token
        params = {
          client_id: result.entra_id_integration.client_id,
          client_secret: result.entra_id_integration.client_secret,
          grant_type: "authorization_code",
          code:,
          redirect_uri: "#{ENV["LAGO_FRONT_URL"]}/auth/entra/callback",
          scope: "openid profile email"
        }

        token_client = LagoHttpClient::Client.new(
          "https://#{result.entra_id_integration.host}/#{result.entra_id_integration.tenant_id}/oauth2/v2.0/token"
        )
        response = token_client.post_url_encoded(params, {})
        result.entra_id_access_token = response["access_token"]
      end

      def check_userinfo(email)
        userinfo_client = LagoHttpClient::Client.new("https://graph.microsoft.com/oidc/userinfo")
        userinfo_headers = {"Authorization" => "Bearer #{result.entra_id_access_token}"}
        response = userinfo_client.get(headers: userinfo_headers)

        response_email = response["email"] || response["preferred_username"]
        raise ValidationError, "entra_id_userinfo_error" if response_email != email

        result.userinfo = response
      end
    end

    class ValidationError < StandardError; end
  end
end
