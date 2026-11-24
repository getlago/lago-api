# frozen_string_literal: true

module Types
  module AgentClaims
    class VerifyInput < Types::BaseInputObject
      graphql_name "VerifyAgentClaimInput"

      argument :claim_code, String, required: true
      argument :storefront_id, ID, required: true
      argument :verification_code, String, required: true
    end
  end
end
