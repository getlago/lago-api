# frozen_string_literal: true

module FindsAgentStorefront
  extend ActiveSupport::Concern

  private

  def find_agent_storefront(id)
    storefront = ::Integrations::AgentStorefrontIntegration.find_by(id:)
    storefront if storefront&.organization&.agent_storefront_enabled?
  end
end
