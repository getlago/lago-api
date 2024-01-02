# frozen_string_literal: true
module Pinet
  class Client
    PINET_API_URL = ENV.fetch('PINET_API_URL', 'https://api.pinpayments.com/1/charges')

    def initialize(api_key: nil)
      @api_key = api_key
    end

    def conn
      @conn ||= Faraday.new
    end

    def charge(charge_body)
      # Fake response for testing purposes
      OpenStruct.new({
        id: SecureRandom.uuid,
        amount: charge_body[:amount],
        currency: charge_body[:currency],
        status: 'succeeded',
      })
    end
  end
end
