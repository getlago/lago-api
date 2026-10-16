# frozen_string_literal: true

module Auth
  module Okta
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

      def check_okta_integration(email)
        email_domain = email.split("@").last
        okta_integration = ::Integrations::OktaIntegration
          .where("settings->>'domain' IS NOT NULL")
          .where("settings->>'domain' = ?", email_domain)
          .first

        raise ValidationError, "domain_not_configured" if okta_integration.blank?

        result.okta_integration = okta_integration
      end

      # Ties the session to the organization and identity provider that authenticated the user.
      def sso_token_claims
        {
          sso_organization_id: result.okta_integration.organization_id,
          sso_issuer: result.okta_integration.sso_issuer
        }
      end

      # NOTE: The identity provider of an integration is chosen by its organization, so it only
      #       vouches for that organization's users. An existing user joins another one through an
      #       invite accepted with a login that organization already trusts.
      def user_trusted_by_integration?(user)
        user.nil? ||
          user.previously_new_record? ||
          user.memberships.active.exists?(organization_id: result.okta_integration.organization_id)
      end

      def integration_organization_allows_login_method?
        result.okta_integration.organization.authentication_methods.include?(Organizations::AuthenticationMethods::OKTA)
      end

      def login_method_not_authorized_failure
        result.single_validation_failure!(
          error_code: "login_method_not_authorized",
          field: Organizations::AuthenticationMethods::OKTA
        )
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

      def check_userinfo(email)
        userinfo_client = LagoHttpClient::Client.new("https://#{result.okta_integration.host}/oauth2/v1/userinfo", block_private_addresses: true)
        userinfo_headers = {"Authorization" => "Bearer #{result.okta_access_token}"}
        response = userinfo_client.get(headers: userinfo_headers)

        raise ValidationError, "okta_userinfo_error" if response["email"] != email

        result.userinfo = response
      end
    end

    class ValidationError < StandardError; end
  end
end
