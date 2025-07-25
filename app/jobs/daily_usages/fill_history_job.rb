# frozen_string_literal: true

module DailyUsages
  class FillHistoryJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ANALYTICS"])
        :analytics
      else
        :long_running
      end
    end

    def perform(subscription:, from_date:, to_date: nil, sandbox: false)
      DailyUsages::FillHistoryService.call!(subscription:, from_date:, to_date:, sandbox:)
    end
  end
end
