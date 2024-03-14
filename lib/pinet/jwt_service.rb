# frozen_string_literal: true

require 'jwt'

module Pinet
  class JwtService
    EXPIRATION_PERIOD = 3600 # unit: seconds

    def self.create_jwt(private_key: nil, key_id: nil)
      iat = Time.now.utc.to_i
      exp = iat + EXPIRATION_PERIOD

      payload = {
        'iss' => ENV['MEMBERSHIP_ORG_ID'],
        'sub' => ENV['PUBLISHER_ID'],
        'iat' => iat,
        'exp' => exp,
      }

      private_key = OpenSSL::PKey::RSA.new(private_key || ENV['PUBLISHER_PRIVATE_KEY_FROM_JSON'])
      kid = key_id || ENV['PUBLISHER_PRIVATE_KEY_ID_FROM_JSON']

      additional_headers = { 'kid' => kid }
      JWT.encode(payload, private_key, 'RS256', additional_headers)
    end
  end
end
