# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
