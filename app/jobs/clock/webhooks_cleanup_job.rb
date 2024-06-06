# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ApplicationJob
    prepend SentryCronConcern

    queue_as 'clock'

    def perform(*)
      Webhook.where('updated_at < ?', 90.days.ago).destroy_all
    end
  end
end
