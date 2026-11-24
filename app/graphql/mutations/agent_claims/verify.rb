# frozen_string_literal: true

module Mutations
  module AgentClaims
    class Verify < BaseMutation
      include ThrottlesAuthAttempts
      include FindsAgentStorefront

      graphql_name "VerifyAgentClaim"
      description "Verifies the code mailed to the owner and claims the agent"

      input_object_class Types::AgentClaims::VerifyInput

      field :claimed_at, GraphQL::Types::ISO8601DateTime, null: false
      field :status, String, null: false

      def resolve(storefront_id:, claim_code:, verification_code:)
        return too_many_attempts_error if throttled?(claim_code)

        storefront = find_agent_storefront(storefront_id)
        return not_found_error(resource: "agent_storefront") unless storefront

        result = ::Agents::Claims::VerifyService.call(storefront:, params: {claim_code:, verification_code:})

        if result.success?
          {status: result.claim.public_status, claimed_at: result.claim.verified_at}
        else
          result_error(result)
        end
      end

      private

      def throttled?(claim_code)
        ::Auth::AttemptsThrottle.hit!(:agent_claim_per_ip, client_ip) ||
          ::Auth::AttemptsThrottle.hit!(:agent_claim_verify_per_code, ::Agents::Claim.normalize_code(claim_code))
      end
    end
  end
end
