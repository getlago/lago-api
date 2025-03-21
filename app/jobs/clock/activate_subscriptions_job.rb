# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    unique :until_executed, on_conflict: :log

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
