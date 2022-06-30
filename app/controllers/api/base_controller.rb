# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    include Pagination

    before_action :authenticate

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

    def validation_errors(error_result)
      render(
        json: {
          status: 422,
          error: 'Unprocessable entity',
          message: error_result.error,
          error_details: error_result.error_details,
        },
        status: :unprocessable_entity,
      )
    end

    def not_found_error
      render(
        json: {
          status: 404,
          error: 'Not Found',
        },
        status: :not_found
      )
    end

    def forbidden_error(error_result)
      render(
        json: {
          status: 403,
          error: 'Forbidden',
          message: error_result.error,
          error_details: error_result.error_details,
        },
        status: :forbidden
      )
    end

    def render_error_response(error_result)
      if error_result.error_code == 'not_found'
        not_found_error
      elsif error_result.error_code == 'forbidden'
        forbidden_error(error_result)
      else
        validation_errors(error_result)
      end
    end

    def current_organization(api_key = nil)
      @current_organization ||= Organization.find_by(api_key: api_key)
    end
  end
end
