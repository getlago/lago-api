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
    include Trackable

    rescue_from ActionController::ParameterMissing, with: :bad_request_error

    private

    attr_reader :current_api_key, :current_organization

    def authenticate
      return unauthorized_error unless auth_token

      @current_api_key = ApiKey.find_by(value: auth_token)

      return unauthorized_error unless current_api_key

      @current_organization = current_api_key.organization
      true
    end

    def auth_token
      request.headers['Authorization']&.split(' ')&.second
    end

    def set_context_source
      CurrentContext.source = 'api'
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
      (request.method == 'GET') ? 'read' : 'write'
    end
  end
end
