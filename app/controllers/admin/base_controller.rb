# frozen_string_literal: true

require 'googleauth'

module Admin
  class BaseController < ApplicationController
    before_action :authenticate

    private

    def authenticate
      auth_header = request.headers['Authorization']

      return unauthorized_error unless auth_header

      token = auth_header.split(' ').second
      payload = Google::Auth::IDTokens::verify_oidc token, aud: ENV['GOOGLE_AUTH_CLIENT_ID']

      CurrentContext.email = payload['email']

      true
    rescue Google::Auth::IDTokens::SignatureError
      return unauthorized_error
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
  end
end
