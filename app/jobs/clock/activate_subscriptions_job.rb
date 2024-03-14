# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    unique :until_executed, on_conflict: :log


    def perform(sentry)
      self.mixin_sentry_cron(senty)
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
