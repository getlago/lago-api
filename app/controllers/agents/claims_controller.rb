# frozen_string_literal: true

module Agents
  class ClaimsController < BaseController
    before_action :authenticate_billing_token, only: %i[create_code show]

    def create_code
      result = Agents::Claims::IssueCodeService.call(registration:)

      if result.success?
        render(json: {claim_code: Agents::Claim.format_code(result.code), claim_url: storefront.claim_url, status: result.claim.public_status})
      else
        render_error_response(result)
      end
    end

    def show
      # Without a customer there is nothing claimed: the merchant deleted it, and the next enrollment resets the claims.
      claim = registration.claims.order(created_at: :desc).first if registration.customer
      render(json: claim_json(claim))
    end

    # The two calls behind the claim page. No token: the claim code is what the owner holds.
    def start
      return if throttled?(:agent_claim_per_ip, request.remote_ip) || throttled?(:agent_claim_mail_per_code, normalized_code)

      result = Agents::Claims::StartService.call(storefront:, params: params.permit(:claim_code, :email))

      if result.success?
        render(json: {status: result.claim.public_status, expires_in: Agents::Claim::VERIFICATION_TTL.to_i})
      elsif too_many_requests?(result)
        render_too_many_requests
      else
        render_error_response(result)
      end
    end

    def verify
      return if throttled?(:agent_claim_per_ip, request.remote_ip) || throttled?(:agent_claim_verify_per_code, normalized_code)

      result = Agents::Claims::VerifyService.call(storefront:, params: params.permit(:claim_code, :verification_code))

      if result.success?
        render(json: {status: result.claim.public_status, claimed_at: result.claim.verified_at.iso8601})
      else
        render_error_response(result)
      end
    end

    private

    def normalized_code
      Agents::Claim.normalize_code(params[:claim_code])
    end

    def claim_json(claim)
      {
        registration_id: registration.id,
        status: claim&.public_status || Agents::Claim::PUBLIC_STATUSES["issued"],
        claimed_at: claim&.verified_at&.iso8601
      }
    end
  end
end
