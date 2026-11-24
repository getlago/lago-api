# frozen_string_literal: true

module Resolvers
  class AgentClaimPageResolver < Resolvers::BaseResolver
    include FindsAgentStorefront

    description "Query the names shown on the public claim page of an agent storefront"

    argument :storefront_id, ID, required: true

    type Types::AgentClaims::Page, null: true

    def resolve(storefront_id:)
      find_agent_storefront(storefront_id) || not_found_error(resource: "agent_storefront")
    end
  end
end
