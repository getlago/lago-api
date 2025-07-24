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

    def perform(subscription:, from_datetime:, to_datetime: nil, sandbox: false)
      DailyUsages::FillHistoryService.call!(subscription:, from_datetime:, to_datetime:, sandbox:)
    end
  end
end
