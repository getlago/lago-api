# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    include Pagination
    include Common
    include ApiErrors

    # Prepended, so that it runs before the authentication and authorization callbacks and
    # 401 and 403 responses carry the header too. Keyed on the path rather than set by the
    # v2 controllers: every /api/v2 path is beta by contract, including those still served
    # by v1 controllers.
    prepend_before_action :set_beta_header!, if: :api_v2_request?

    before_action :authenticate
    before_action :set_context_source
    before_action :track_api_key_usage
    before_action :authorize
    include Trackable
    include ApiLoggable

    rescue_from ActionController::ParameterMissing, with: :bad_request_error

    private

    attr_reader :current_api_key, :current_organization

    def ensure_organization_uses_clickhouse
      forbidden_error(code: "endpoint_not_available") unless current_organization.clickhouse_events_store?
    end

    def authenticate
      return unauthorized_error unless auth_token

      @current_api_key, organization = ApiKeys::CacheService.call(auth_token, with_cache: cached_api_key?)
      return unauthorized_error unless current_api_key

      @current_organization = organization
      true
    end

    def auth_token
      request.headers["Authorization"]&.split(" ")&.second
    end

    def set_context_source
      CurrentContext.source = "api"
      CurrentContext.api_key_id = current_api_key.id
      Sentry.set_tags(api_key_id: current_api_key.id)
    end

    def set_beta_header!
      response.set_header("X-Lago-Endpoint-Status", "beta")
    end

    def api_v2_request?
      request.path.start_with?("/api/v2/")
    end

    def track_api_key_usage
      return unless track_api_key_usage?

      Rails.cache.write(
        "api_key_last_used_#{current_api_key.id}",
        Time.current.iso8601
      )
    end

    def track_api_key_usage?
      true
    end

    def authorize
      return if current_api_key.permit?(resource_name, mode)

      forbidden_error(code: "#{mode}_action_not_allowed_for_#{resource_name}")
    end

    def resource_name
      nil
    end

    def mode
      (request.method == "GET") ? "read" : "write"
    end

    def cached_api_key?
      false
    end
  end
end
