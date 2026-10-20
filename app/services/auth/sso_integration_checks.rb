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
  end
end
