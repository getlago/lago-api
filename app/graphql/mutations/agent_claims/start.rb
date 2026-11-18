# frozen_string_literal: true

module Mutations
  module AgentClaims
    class Start < BaseMutation
      include ThrottlesAuthAttempts
      include FindsAgentStorefront

      graphql_name "StartAgentClaim"
      description "Mails a verification code to the owner who typed an agent's claim code"

      input_object_class Types::AgentClaims::StartInput

      field :expires_in, Integer, null: false
      field :status, String, null: false

      def resolve(storefront_id:, claim_code:, email:)
        return too_many_attempts_error if throttled?(claim_code)

        storefront = find_agent_storefront(storefront_id)
        return not_found_error(resource: "agent_storefront") unless storefront

        result = ::Agents::Claims::StartService.call(storefront:, params: {claim_code:, email:})

        if result.success?
          {status: result.claim.public_status, expires_in: ::Agents::Claim::VERIFICATION_TTL.to_i}
        elsif mailbox_throttled?(result)
          too_many_attempts_error
        else
          result_error(result)
        end
      end

      private

      def throttled?(claim_code)
        ::Auth::AttemptsThrottle.hit!(:agent_claim_per_ip, client_ip) ||
          ::Auth::AttemptsThrottle.hit!(:agent_claim_mail_per_code, ::Agents::Claim.normalize_code(claim_code))
      end

      def mailbox_throttled?(result)
        result.error.is_a?(BaseService::MethodNotAllowedFailure) && result.error.code == "too_many_requests"
      end
    end
  end
end
