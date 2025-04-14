# frozen_string_literal: true

module Subscriptions
  class RecalculateUsageJob < ApplicationJob
    queue_as :default

    unique :until_executed, on_conflict: :log

    def perform(subscription)
      Subscriptions::RecalculateUsageService.call!(subscription:)
    end

    def lock_key_arguments
      [arguments]
    end
  end
end
