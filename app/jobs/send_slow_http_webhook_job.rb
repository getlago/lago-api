# frozen_string_literal: true

class SendSlowHttpWebhookJob < ApplicationJob
  queue_as :webhook_low_priority

  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.warn("Discarding #{job.class.name} after 3 retries due to: #{error.message}")
  end

  def perform(webhook)
    Webhooks::SendHttpService.call(webhook:)
  end
end
