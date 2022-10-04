# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscriptions::ActivateService.new.activate_all_pending
    end
  end
end
