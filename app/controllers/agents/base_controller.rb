# frozen_string_literal: true

module Agents
  class BaseController < ApplicationController
    include Api::V1Errors

    before_action :find_storefront

    private

    attr_reader :storefront, :registration

    def find_storefront
      @storefront = Integrations::AgentStorefrontIntegration.find_by(id: params[:storefront_id])
      not_found_error(resource: "agent_storefront") unless storefront&.organization&.agent_storefront_enabled?
    end

    def bearer_token
      request.authorization.to_s[/\ABearer (.+)\z/i, 1]
    end

    def authenticate_billing_token
      result = Agents::Auth::VerifyTokenService.call(storefront:, token: bearer_token, scope: Agents::Auth::ChallengeService::BILLING_SCOPE)
      if result.success?
        @registration = result.registration
      else
        render_error_response(result)
      end
    end

    def throttled?(rule, identifier)
      return false unless ::Auth::AttemptsThrottle.hit!(rule, identifier)

      render_too_many_requests
      true
    end

    # A service counts an attempt itself when the limit only applies once its checks passed.
    def too_many_requests?(result)
      result.error.is_a?(BaseService::MethodNotAllowedFailure) && result.error.code == "too_many_requests"
    end

    def render_too_many_requests
      render(json: {status: 429, error: "Too Many Requests", code: "too_many_requests"}, status: :too_many_requests)
    end
  end
end
