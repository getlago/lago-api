# frozen_string_literal: true

class SendHttpWebhookJob < ApplicationJob
  queue_as { SendWebhookJob.queue_for }

  # Retry in case of in transactional webhooks, discard after 3 retries
  retry_on ActiveJob::DeserializationError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.warn("Discarding #{job.class.name} after 3 retries due to: #{error.message}")
  end

  # Retry when S3 throttles queries
  retry_on "Aws::S3::Errors::SlowDown", wait: :polynomially_longer, attempts: 6

  def perform(webhook)
    Webhooks::SendHttpService.call(webhook:)
  end
end
