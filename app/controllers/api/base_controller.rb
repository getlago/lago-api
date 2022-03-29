# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      auth_header = request.headers['Authorization']

      return unauthorized_error unless auth_header

      api_key = auth_header.split(' ').second

      return unauthorized unless api_key
      return unauthorized_error unless current_organization(api_key)

      true
    end

    def unauthorized_error
      render json: { message: 'Unauthorized' }, status: :unauthorized
    end

    def validation_errors(errors)
      render(
        json: {
          message: 'Unprocessable entity',
          errors: errors
        },
        status: :unprocessable_entity
      )
    end

    def current_organization(api_key = nil)
      @current_organization ||= Organization.find_by(api_key: api_key)
    end
  end
end
