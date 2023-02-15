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
      return unless current_organization&.webhook_url?

      payload = {
        webhook_type:,
        object_type:,
        object_type => object_serializer.serialize,
      }

      preprocess_webhook(current_webhook, payload)

      http_client = LagoHttpClient::Client.new(current_organization.webhook_url)
      headers = generate_headers(payload)
      response = http_client.post_with_response(payload, headers)

      succeed_webhook(current_webhook, response)
    rescue LagoHttpClient::HttpError => e
      fail_webhook(current_webhook, e)

      # NOTE: By default, Lago is retrying 3 times a webhook
      return if current_webhook.retries == ENV.fetch('LAGO_WEBHOOK_ATTEMPTS', 3).to_i

      SendWebhookJob.set(wait: wait_value)
        .perform_later(webhook_type, object, options, current_webhook.id)
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

    def current_webhook
      @current_webhook ||= current_organization.webhooks.find_or_initialize_by(
        id: webhook_id,
      )
    end

    def preprocess_webhook(webhook, payload)
      webhook.webhook_type = webhook_type
      webhook.endpoint = current_organization.webhook_url
      webhook.object_id = object.is_a?(Hash) ? object.fetch(:id, nil) : object&.id
      webhook.object_type = object.is_a?(Hash) ? object.fetch(:class, nil) : object&.class&.to_s
      webhook.payload = payload.to_json
      webhook.retries += 1 if webhook.failed?
      webhook.last_retried_at = Time.zone.now if webhook.retries.positive?
    end

    def succeed_webhook(webhook, response)
      webhook.http_status = response&.code&.to_i
      webhook.response = response&.body&.presence || {}
      webhook.succeeded!
    end

    def fail_webhook(webhook, error)
      webhook.http_status = error.error_code
      webhook.response = error.error_body
      webhook.failed!
    end

    def wait_value
      # NOTE: This is based on the Rails Active Job wait algorithm
      executions = current_webhook.retries
      ((executions**4) + (Kernel.rand * (executions**4) * 0.15)) + 2
    end
  end
end
