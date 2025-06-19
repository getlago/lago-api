# frozen_string_literal: true

module DailyUsages
  class FillHistoryJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_USAGES_BACKFILL"])
        :usages_backfill
      else
        :long_running
      end
    end

    def perform(subscription:, from_datetime:, sandbox: false)
      DailyUsages::FillHistoryService.call!(subscription:, from_datetime:, sandbox:)
    end
  end
end
