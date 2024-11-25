# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    include SentryCronConcern

    queue_as 'clock'
    limits_concurrency to: 1, key: 'activate_subscription', duration: 1.hour

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
