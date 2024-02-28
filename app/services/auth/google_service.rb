# frozen_string_literal: true

module Auth
  class GoogleService
    BASE_SCOPE = %w[profile email openid].freeze

    def authorize(request)
      client_id = Google::Auth::ClientId.new(ENV['GOOGLE_AUTH_CLIENT_ID'], ENV['GOOGLE_AUTH_CLIENT_SECRET'])
      authorizer = Google::Auth::WebUserAuthorizer.new(client_id, BASE_SCOPE, nil, '/auth/google/callback')
      authorizer.get_authorization_url(request:)
    end
  end
end
