# frozen_string_literal: true

module Agents
  class AuthController < BaseController
    def challenge
      return if throttled?(:agent_challenge_per_ip, request.remote_ip)
      return if throttled?(:agent_challenge_per_key, params[:public_key].to_s)

      result = Agents::Auth::ChallengeService.call(storefront:, public_key: params[:public_key], purpose: params[:purpose])

      if result.success?
        render(
          json: {
            challenge_id: result.challenge_id,
            message: Base64.urlsafe_encode64(result.message, padding: false),
            signing_algorithm: "Ed25519",
            expires_at: result.expires_at
          }
        )
      else
        render_error_response(result)
      end
    end

    def signup
      prove("signup")
    end

    def token
      prove("authenticate")
    end

    def revoke
      return if throttled?(:agent_proof_per_ip, request.remote_ip)

      result = proof_result("revoke")

      if result.success?
        render(json: {registration_id: result.registration.id, status: result.registration.status})
      else
        render_error_response(result)
      end
    end

    def me
      result = Agents::Auth::VerifyTokenService.call(storefront:, token: request.authorization.to_s[/\ABearer (.+)\z/i, 1])

      if result.success?
        render(json: {registration_id: result.registration.id, scope: storefront.scope, status: result.registration.status})
      else
        render_error_response(result)
      end
    end

    private

    def prove(purpose)
      return if throttled?(:agent_proof_per_ip, request.remote_ip)

      result = proof_result(purpose)

      if result.success?
        render(
          json: {
            registration_id: result.registration.id,
            created: result.created,
            access_token: result.access_token,
            token_type: "Bearer",
            expires_in: Agents::Auth::ProofService::TOKEN_TTL.to_i,
            scope: storefront.scope
          }
        )
      else
        render_error_response(result)
      end
    end

    def proof_result(purpose)
      Agents::Auth::ProofService.call(storefront:, challenge_id: params[:challenge_id], signature: params[:signature], purpose:)
    end
  end
end
