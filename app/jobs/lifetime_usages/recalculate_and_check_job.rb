# frozen_string_literal: true

module LifetimeUsages
  class RecalculateAndCheckJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_BILLING'])
        :billing
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(lifetime_usage)
      LifetimeUsages::RecalculateAndCheckService.call(lifetime_usage:)
    end
  end
end
