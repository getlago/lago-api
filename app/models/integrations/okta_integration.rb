# frozen_string_literal: true

module Integrations
  class OktaIntegration < BaseIntegration
    validates :client_secret, :client_id, :domain, :organization_name, presence: true

    settings_accessors :client_id, :domain, :organization_name
    secrets_accessors :client_secret
  end
end
