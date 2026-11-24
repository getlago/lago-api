# frozen_string_literal: true

module Types
  module AgentClaims
    class StartInput < Types::BaseInputObject
      graphql_name "StartAgentClaimInput"

      argument :claim_code, String, required: true
      argument :email, String, required: true
      argument :storefront_id, ID, required: true
    end
  end
end
