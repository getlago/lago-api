# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    include Pagination
    include Common

    before_action :authenticate
    before_action :set_context_source
    include Trackable

    private

    def authenticate
      auth_header = request.headers['Authorization']

      return unauthorized_error unless auth_header

      api_key = auth_header.split(' ').second

      return unauthorized_error unless api_key
      return unauthorized_error unless current_organization(api_key)

      true
    end

    def unauthorized_error
      render(
        json: {
          status: 401,
          error: 'Unauthorized',
        },
        status: :unauthorized,
      )
    end

    def validation_errors(errors:)
      render(
        json: {
          status: 422,
          error: 'Unprocessable Entity',
          code: 'validation_errors',
          error_details: errors,
        },
        status: :unprocessable_entity,
      )
    end

    def method_not_allowed_error(code:)
      render(
        json: {
          status: 405,
          error: 'Method Not Allowed',
          code: code,
        },
        status: :method_not_allowed,
      )
    end

    def render_error_response(error_result)
      case error_result.error
      when BaseService::NotFoundFailure
        not_found_error(resource: error_result.error.resource)
      when BaseService::MethodNotAllowedFailure
        method_not_allowed_error(code: error_result.error.code)
      when BaseService::ValidationFailure
        validation_errors(errors: error_result.error.messages)
      else
        raise(error_result.error)
      end
    end

    def current_organization(api_key = nil)
      @current_organization ||= Organization.find_by(api_key: api_key)
    end

    def set_context_source
      CurrentContext.source = 'api'
    end
  end
end
