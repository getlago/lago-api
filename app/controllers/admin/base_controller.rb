# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    include ApiErrors

    before_action :authenticate
    before_action :set_context_source

    private

    def authenticate
      auth_header = request.headers["Authorization"]

      return unauthorized_error unless auth_header

      # Support both Google Auth and API key authentication
      if auth_header.start_with?("Bearer ")
        authenticate_with_google_auth(auth_header)
      elsif auth_header.start_with?("Api-Key ")
        authenticate_with_api_key(auth_header)
      else
        unauthorized_error
      end
    end

    def authenticate_with_google_auth(auth_header)
      token = auth_header.split(" ").second
      payload = Google::Auth::IDTokens.verify_oidc(
        token,
        aud: ENV["GOOGLE_AUTH_CLIENT_ID"]
      )

      CurrentContext.email = payload["email"]

      true
    rescue Google::Auth::IDTokens::SignatureError
      unauthorized_error
    end

    def authenticate_with_api_key(auth_header)
      api_key = auth_header.split(" ").second
      admin_api_key = ENV["LAGO_ADMIN_API_KEY"]

      return unauthorized_error unless admin_api_key.present? && api_key == admin_api_key

      CurrentContext.email = "admin-api@lago.com"

      true
    end

    def set_context_source
      CurrentContext.source = "admin"
      CurrentContext.api_key_id = nil
    end
  end
end
