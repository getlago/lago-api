# frozen_string_literal: true

class SendHttpWebhookJob < ApplicationJob
  queue_as do
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_WEBHOOK"])
      :webhook_worker
    else
      :webhook
    end
  end

  # Retry in case of in transactional webhooks, discard after 3 retries
  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.warn("Discarding #{job.class.name} after 3 retries due to: #{error.message}")
  end

  def perform(webhook)
    if webhook.webhook_endpoint.slow_response? && pending_non_slow_webhooks?
      self.class.perform_later(webhook)
      return
    end

    Webhooks::SendHttpService.call(webhook:)
  end

  private

  def pending_non_slow_webhooks?
    Webhook.pending
      .joins(:webhook_endpoint)
      .where(webhook_endpoints: {slow_response: false})
      .exists?
  end
end
