# frozen_string_literal: true

module Agents
  class BaseController < ApplicationController
    include ApiErrors

    before_action :find_storefront

    private

    attr_reader :storefront

    def find_storefront
      @storefront = Integrations::AgentStorefrontIntegration.find_by(id: params[:storefront_id])
      not_found_error(resource: "agent_storefront") unless storefront&.organization&.agent_storefront_enabled?
    end

    def throttled?(rule, identifier)
      return false unless ::Auth::AttemptsThrottle.hit!(rule, identifier)

      render(json: {status: 429, error: "Too Many Requests", code: "too_many_requests"}, status: :too_many_requests)
      true
    end
  end
end
