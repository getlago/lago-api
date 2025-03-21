# frozen_string_literal: true

module Clock
  class InboundWebhooksCleanupJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as "clock"

    def perform
      InboundWebhook.where("updated_at < ?", 90.days.ago).destroy_all
    end
  end
end
