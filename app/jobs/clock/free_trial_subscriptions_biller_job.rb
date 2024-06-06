# frozen_string_literal: true

module Clock
  class FreeTrialSubscriptionsBillerJob < ApplicationJob
    prepend SentryCronConcern

    queue_as 'clock'

    def perform(*)
      Subscriptions::FreeTrialBillingService.call
    end
  end
end
