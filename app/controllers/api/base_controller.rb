# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    include Pagination
    include Common
    include ApiErrors

    before_action :authenticate
    before_action :set_context_source
    before_action :track_api_key_usage
    before_action :authorize
    before_action :validate_page_size
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
    end

    def set_beta_header!
      response.set_header("X-Lago-Endpoint-Status", "beta")
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

    def max_page_size
      PER_PAGE # 100 by default, see `Pagination` concern
    end

    def validate_page_size
      return if params[:per_page].blank?
      return if params[:per_page].to_i <= max_page_size

      validation_errors(errors: {per_page: ["must_be_less_than_or_equal_to_#{max_page_size}"]})
    end
  end
end
