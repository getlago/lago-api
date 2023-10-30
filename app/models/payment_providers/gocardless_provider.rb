# frozen_string_literal: true

module PaymentProviders
  class GocardlessProvider < BaseProvider
    SUCCESS_REDIRECT_URL = 'https://gocardless.com/'

    validates :access_token, presence: true
    validates :success_redirect_url, url: true, allow_nil: true, length: { maximum: 1024 }

    def self.auth_site
      if Rails.env.production?
        'https://connect.gocardless.com'
      else
        'https://connect-sandbox.gocardless.com'
      end
    end

    def environment
      if Rails.env.production?
        :live
      else
        :sandbox
      end
    end

    def access_token=(access_token)
      push_to_secrets(key: 'access_token', value: access_token)
    end

    def access_token
      get_from_secrets('access_token')
    end
  end
end
