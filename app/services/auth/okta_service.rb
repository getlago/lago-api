# frozen_string_literal: true

module Auth
  class OktaService < BaseService
    def authorize(email:)
      email_domain = email.split('@').last
      okta_integration = ::Integrations::OktaIntegration
        .where('settings->>\'domain\' IS NOT NULL')
        .where('settings->>\'domain\' = ?', email_domain)
        .first

      return result.single_validation_failure!(error_code: 'domain_not_configured') if okta_integration.blank?

      initialize_state

      params = {
        client_id: okta_integration.client_id,
        response_type: 'code',
        response_mode: 'query',
        scope: 'openid profile email',
        redirect_uri: "#{ENV['LAGO_FRONT_URL']}/auth/okta/callback",
      }
      result.url = URI::HTTPS.build(
        host: "#{okta_integration.organization_name.downcase}.okta.com",
        path: '/oauth2/default/v1/authorize',
        query: params.to_query,
      ).to_s

      result
    end

    private

    def initialize_state
      CurrentContext.okta_state ||= "state-#{SecureRandom.uuid}"
    end
  end
end
