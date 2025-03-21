# frozen_string_literal: true

module Clock
  class InboundWebhooksRetryJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as "clock"

    def perform
      InboundWebhook.retriable.find_each do |inbound_webhook|
        InboundWebhooks::ProcessJob.perform_later(inbound_webhook:)
      end
    end
  end
end
