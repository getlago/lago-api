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

      organization = Organization.find_by(api_key: api_key)

      return unauthorized_error unless organization

      true
    end

    def unauthorized_error
      render json: { message: 'Unauthorized' }, status: :unauthorized
    end
  end
end
