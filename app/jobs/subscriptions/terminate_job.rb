# frozen_string_literal: true

module Subscriptions
  class TerminateJob < ApplicationJob
    queue_as 'billing'

    def perform(subscription, timestamp)
      result = Subscriptions::TerminateService.new.terminate_and_start_next(
        subscription: subscription,
        timestamp: timestamp,
      )

      raise result.throw_error unless result.success?
    end
  end
end
