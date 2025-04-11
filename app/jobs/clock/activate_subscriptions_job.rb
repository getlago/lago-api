# frozen_string_literal: true

module Clock
  class ActivateSubscriptionsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending
    end
  end
end
