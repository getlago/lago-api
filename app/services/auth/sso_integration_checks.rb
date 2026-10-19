# frozen_string_literal: true

module Auth
  # Shared by the Okta and Entra ID services, which define `sso_integration` and `sso_login_method`.
  module SsoIntegrationChecks
    private

    # Ties the session to the organization and identity provider that authenticated the user.
    def sso_token_claims
      {
        sso_organization_id: sso_integration.organization_id,
        sso_issuer: sso_integration.sso_issuer
      }
    end

    # NOTE: The identity provider of an integration is chosen by its organization, so it only
    #       vouches for the users of the organizations that accept its sessions. An existing user
    #       joins another one through an invite accepted with a login that organization trusts.
    def user_trusted_by_integration?(user)
      user.nil? ||
        user.previously_new_record? ||
        sso_cross_organization_sessions? ||
        user.active_organizations.includes(:integrations).any? do
          it.accessible_by_session?(login_method: sso_login_method, **sso_token_claims)
        end
    end

    def integration_organization_allows_login_method?
      sso_integration.organization.authentication_methods.include?(sso_login_method) ||
        sso_cross_organization_sessions?
    end

    def sso_cross_organization_sessions?
      sso_integration.organization.feature_flag_enabled?(:sso_cross_organization_sessions)
    end

    def login_method_not_authorized_failure
      result.single_validation_failure!(error_code: "login_method_not_authorized", field: sso_login_method)
    end
  end
end
