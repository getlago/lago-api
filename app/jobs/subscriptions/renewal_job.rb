# frozen_string_literal: true

module Subscriptions
  class RenewalJob < ApplicationJob
    queue_as 'billing'

    def perform(timebased_event)
      result = Subscriptions::RenewalService.new(timebased_event:, async: false).call

      result.raise_if_error!
    end
  end
end
