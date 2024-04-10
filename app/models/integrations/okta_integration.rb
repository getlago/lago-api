# frozen_string_literal: true

module Integrations
  class OktaIntegration < BaseIntegration
    validates :client_secret, :client_id, :domain, presence: true

    settings_accessors :client_id, :domain
    secrets_accessors :client_secret
  end
end
