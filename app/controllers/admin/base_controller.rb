# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include ApiErrors

    before_action :authenticate
    before_action :set_context_source

    private

    def authenticate
      auth_header = request.headers['Authorization']

      return unauthorized_error unless auth_header

      token = auth_header.split(' ').second
      payload = Google::Auth::IDTokens.verify_oidc(
        token,
        aud: ENV['GOOGLE_AUTH_CLIENT_ID'],
      )

      CurrentContext.email = payload['email']

      true
    rescue Google::Auth::IDTokens::SignatureError
      unauthorized_error
    end

    def set_context_source
      CurrentContext.source = 'admin'
    end
  end
end
