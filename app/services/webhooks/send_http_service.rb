# frozen_string_literal: true

module Webhooks
  class SendHttpService < ::BaseService
    def initialize(webhook:)
      @webhook = webhook

      super
    end

    def call
      webhook.endpoint = webhook.webhook_endpoint.webhook_url

      http_client = LagoHttpClient::Client.new(webhook.webhook_endpoint.webhook_url)
      response = http_client.post_with_response(webhook.payload, webhook.generate_headers)

      mark_webhook_as_succeeded(response)
    rescue LagoHttpClient::HttpError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Net::HTTPBadResponse,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::EPIPE,
      OpenSSL::SSL::SSLError,
      SocketError,
      EOFError => e
      mark_webhook_as_failed(e)

      # NOTE: By default, Lago is retrying 3 times a webhook
      return if webhook.retries >= ENV.fetch('LAGO_WEBHOOK_ATTEMPTS', 3).to_i

      SendHttpWebhookJob.set(wait: wait_value).perform_later(webhook)
    end

    private

    attr_reader :webhook

    def mark_webhook_as_succeeded(response)
      webhook.http_status = response&.code&.to_i
      webhook.response = response&.body.presence || {}
      webhook.status = :succeeded
      webhook.save!
    end

    def mark_webhook_as_failed(error)
      if error.is_a?(LagoHttpClient::HttpError)
        webhook.http_status = error.error_code
        webhook.response = error.error_body
      else
        webhook.response = error.message
      end
      webhook.retries += 1
      webhook.last_retried_at = Time.zone.now
      webhook.status = :failed
      webhook.save!
    end

    def wait_value
      # NOTE: This is based on the Rails Active Job wait algorithm
      executions = webhook.retries
      ((executions**4) + (Kernel.rand * (executions**4) * 0.15)) + 2
    end
  end
end
