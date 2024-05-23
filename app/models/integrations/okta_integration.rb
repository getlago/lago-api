# frozen_string_literal: true

module Integrations
  class OktaIntegration < BaseIntegration
    validates :client_secret, :client_id, :domain, :organization_name, presence: true
    validate :domain_uniqueness

    settings_accessors :client_id, :domain, :organization_name
    secrets_accessors :client_secret

    private

    def domain_uniqueness
      okta_integration = ::Integrations::OktaIntegration
        .where('settings->>\'domain\' IS NOT NULL')
        .where('settings->>\'domain\' = ?', domain)
        .exists?
      
      errors.add(:domain, 'domain_not_unique') if okta_integration
    end
  end
end
