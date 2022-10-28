# frozen_string_literal: true

module PaymentProviders
  class GocardlessProvider < BaseProvider
    BILLING_REQUEST_REDIRECT_URL = 'https://gocardless.com/'

    validates :access_token, presence: true

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
