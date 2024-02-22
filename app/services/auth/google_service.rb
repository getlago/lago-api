# frozen_string_literal: true

module Auth
  class GoogleService
    AUTHORIZE_URL = 'https://accounts.google.com/o/oauth2/auth'
    BASE_SCOPE = %w[profile email openid].freeze

    def initialize
      @redis_connection = Redis.new(url: ENV['REDIS_URL'])
    end

    def authorize

    end
  end
end
