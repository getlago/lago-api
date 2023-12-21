# frozen_string_literal: true

require 'lago_http_client'

module Webhooks
  # NOTE: Abstract Service, should not be used directly
  class BaseService
    def initialize(object:, options: {}, webhook_id: nil)
      @object = object
      @options = options&.with_indifferent_access
      @webhook_id = webhook_id
    end

    def call
      return resend if webhook_id.present?
      return if current_organization.webhook_endpoints.none?

      payload = {
        webhook_type:,
        object_type:,
        object_type => object_serializer.serialize,
      }

      current_organization.webhook_endpoints.each do |webhook_endpoint|
        webhook = initialize_webhook(webhook_endpoint, payload)
        send_webhook(webhook, webhook_endpoint, payload)
      end
    end

    def resend
      webhook = Webhook.find_by(id: webhook_id)
      return if webhook.blank?

      webhook.retries += 1 if webhook.failed?
      webhook.last_retried_at = Time.zone.now if webhook.retries.positive?
      webhook.endpoint = webhook.webhook_endpoint.webhook_url

      payload = JSON.parse(webhook.payload)
      send_webhook(webhook, webhook.webhook_endpoint, payload)
    end

    private

    attr_reader :object, :options, :webhook_id

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

    def send_webhook(webhook, webhook_endpoint, payload)
      http_client = LagoHttpClient::Client.new(webhook_endpoint.webhook_url)
      headers = generate_headers(webhook.id, webhook_endpoint, payload)
      response = http_client.post_with_response(payload, headers)

      succeed_webhook(webhook, response)
    rescue LagoHttpClient::HttpError,
           Net::OpenTimeout,
           Net::ReadTimeout,
           Errno::ECONNRESET,
           Errno::ECONNREFUSED,
           SocketError,
           EOFError => e
      fail_webhook(webhook, e)

      # NOTE: By default, Lago is retrying 3 times a webhook
      return if webhook.retries >= ENV.fetch('LAGO_WEBHOOK_ATTEMPTS', 3).to_i

      SendWebhookJob.set(wait: wait_value(webhook))
        .perform_later(webhook_type, object, options, webhook.id)
    end

    def generate_headers(webhook_id, webhook_endpoint, payload)
      signature = case webhook_endpoint.signature_algo&.to_sym
                  when :jwt
                    jwt_signature(payload)
                  when :hmac
                    hmac_signature(payload)
      end

      {
        'X-Lago-Signature' => signature,
        'X-Lago-Signature-Algorithm' => webhook_endpoint.signature_algo.to_s,
        'X-Lago-Unique-Key' => webhook_id,
      }
    end

    def jwt_signature(payload)
      JWT.encode(
        {
          data: payload.to_json,
          iss: issuer,
        },
        RsaPrivateKey,
        'RS256',
      )
    end

    def hmac_signature(payload)
      hmac = OpenSSL::HMAC.digest('sha-256', current_organization.api_key, payload.to_json)
      Base64.strict_encode64(hmac)
    end

    def issuer
      ENV['LAGO_API_URL']
    end

    def initialize_webhook(webhook_endpoint, payload)
      webhook = Webhook.new(webhook_endpoint:)
      webhook.webhook_type = webhook_type
      webhook.endpoint = webhook_endpoint.webhook_url
      webhook.object_id = object.is_a?(Hash) ? object.fetch(:id, nil) : object&.id
      webhook.object_type = object.is_a?(Hash) ? object.fetch(:class, nil) : object&.class&.to_s
      webhook.payload = payload.to_json
      webhook.retries += 1 if webhook.failed?
      webhook.last_retried_at = Time.zone.now if webhook.retries.positive?
      webhook.pending!
      webhook
    end

    def succeed_webhook(webhook, response)
      webhook.http_status = response&.code&.to_i
      webhook.response = response&.body.presence || {}
      webhook.succeeded!
    end

    def fail_webhook(webhook, error)
      if error.is_a?(LagoHttpClient::HttpError)
        webhook.http_status = error.error_code
        webhook.response = error.error_body
      else
        webhook.response = error.message
      end
      webhook.failed!
    end

    def wait_value(webhook)
      # NOTE: This is based on the Rails Active Job wait algorithm
      executions = webhook.retries
      ((executions**4) + (Kernel.rand * (executions**4) * 0.15)) + 2
    end
  end
end
