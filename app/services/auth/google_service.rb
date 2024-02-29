# frozen_string_literal: true

module Auth
  class GoogleService < BaseService
    BASE_SCOPE = %w[profile email openid].freeze

    def initialize
      @client_id = Google::Auth::ClientId.new(ENV['GOOGLE_AUTH_CLIENT_ID'], ENV['GOOGLE_AUTH_CLIENT_SECRET'])

      super
    end

    def authorize_url(request)
      authorizer = Google::Auth::WebUserAuthorizer.new(
        client_id,
        BASE_SCOPE,
        nil,
        "#{ENV['LAGO_FRONT_URL']}/auth/google/callback",
      )

      result.url = authorizer.get_authorization_url(request:)

      result
    end

    def login(code)
      authorizer = Google::Auth::UserAuthorizer.new(
        client_id,
        BASE_SCOPE,
        nil,
        "#{ENV['LAGO_FRONT_URL']}/auth/google/callback",
      )

      credentials = authorizer.get_credentials_from_code(code:)
      google_oidc = Google::Auth::IDTokens.verify_oidc(credentials.id_token, aud: ENV['GOOGLE_AUTH_CLIENT_ID'])

      user = User.find_by(email: google_oidc['email'])

      unless user.present? && user.memberships&.active&.any?
        return result.single_validation_failure!(error_code: 'user_does_not_exist')
      end

      UsersService.new.new_token(user)
    rescue Google::Auth::IDTokens::SignatureError
      result.single_validation_failure!(error_code: 'invalid_google_token')
    rescue Signet::AuthorizationError
      result.single_validation_failure!(error_code: 'invalid_google_code')
    end

    private

    attr_reader :client_id
  end
end
