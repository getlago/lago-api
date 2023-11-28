# frozen_string_literal: true

module Webhooks
  class RetryService < ::BaseService
    def initialize(webhook:)
      @webhook = webhook

      super
    end

    def call
      return result.not_found_failure!(resource: 'webhook') unless webhook
      return result.not_allowed_failure!(code: 'is_succeeded') if webhook.succeeded?

      SendWebhookJob.perform_later(
        webhook.webhook_type,
        webhook.object,
        {},
        webhook.id,
      )

      result.webhook = webhook
      result
    end

    private

    attr_reader :webhook
  end
end
