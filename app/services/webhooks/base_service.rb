# frozen_string_literal: true

require 'lago_http_client'

module Webhooks
  # NOTE: Abstract Service, should not be used directly
  class BaseService
    def initialize(object:, options: {})
      @object = object
      @options = options&.with_indifferent_access
    end

    def call
      return unless current_organization&.webhook_url?

      payload = {
        webhook_type:,
        object_type:,
        object_type => object_serializer.serialize,
      }

      http_client = LagoHttpClient::Client.new(current_organization.webhook_url)
      headers = generate_headers(payload)
      http_client.post(payload, headers)
    end

    private

    attr_reader :object, :options

    def object_serializer
      # Empty
    end

    def current_organization
      # Empty
    end

    def webhook_type
      # Empty
    end

    def object_type
      # Empty
    end

    def generate_headers(payload)
      [
        'X-Lago-Signature' => generate_signature(payload),
      ]
    end

    def generate_signature(payload)
      JWT.encode(
        {
          data: payload.to_json,
          iss: issuer,
        },
        RsaPrivateKey,
        'RS256',
      )
    end

    def issuer
      ENV['LAGO_API_URL']
    end
  end
end
