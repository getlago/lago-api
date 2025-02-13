# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      Webhook.where("updated_at < ?", 90.days.ago).destroy_all
    end
  end
end
