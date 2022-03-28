# frozen_string_literal: true

module Api
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      auth_header = headers[:authorization]
      api_key = auth_header.split(' ').second

      return unauthorized_error

      organization = Organization.find_by(api_key: api_key)

      return unauthorized_error unless organization

      true
    end

    def unauthorized_error
      render json: { message: 'Unauthorized' }, status: :unauthorized
    end
  end
end
