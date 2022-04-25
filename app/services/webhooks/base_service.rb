# frozen_string_literal: true

require 'lago_http_client'

module Webhooks
  # NOTE: Abstract Service, should not be used directly
  class BaseService
    def initialize(object)
      @object = object
    end

    def call
      payload = object_serializer
      payload.merge(webhook_type: webhook_type)

      http_client = LagoHttpClient::Client.new(current_organization.webhook_url)
      headers = generate_headers(payload)
      http_client.post(payload, headers)
    end

    private

    attr_reader :object

    def object_serializer
      # Empty
    end

    def current_organization
      # Empty
    end

    def webhook_type
      # Empty
    end

    def generate_headers(payload)
      [
        'X-Lago-Signature' => generate_signature(payload),
      ]
    end

    def generate_signature(payload)
      JWT.encode(
        payload.to_json,
        RsaPrivateKey,
        'RS256',
      )
    end
  end
end
