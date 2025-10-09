# frozen_string_literal: true

module LifetimeUsages
  class RecalculateAndCheckJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    # NOTE: do not pass current usage with perform_later as it will be a huge JSON
    def perform(lifetime_usage, current_usage: nil)
      LifetimeUsages::CalculateService.call!(lifetime_usage:, current_usage:)

      if lifetime_usage.organization.progressive_billing_enabled?
        LifetimeUsages::CheckThresholdsService.call!(lifetime_usage:)
      end
    end

    def lock_key_arguments
      [arguments.first]
    end
  end
end
