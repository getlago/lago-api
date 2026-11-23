# frozen_string_literal: true

module Agents
  class BaseController < ApplicationController
    include Api::V1Errors

    before_action :find_storefront

    private

    attr_reader :storefront

    def find_storefront
      @storefront = Integrations::AgentStorefrontIntegration.find_by(id: params[:storefront_id])
      not_found_error(resource: "agent_storefront") unless storefront&.organization&.agent_storefront_enabled?
    end

    def throttled?(rule, *identifiers)
      return false unless ::Auth::AttemptsThrottle.hit!(rule, *identifiers)

      too_many_requests
      true
    end

    def limit_reached?(rule, *identifiers)
      return false unless ::Auth::AttemptsThrottle.at_limit?(rule, *identifiers)

      too_many_requests
      true
    end

    def too_many_requests
      render(json: {status: 429, error: "Too Many Requests", code: "too_many_requests"}, status: :too_many_requests)
    end
  end
end
