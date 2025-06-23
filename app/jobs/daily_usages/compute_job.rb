# frozen_string_literal: true

module DailyUsages
  class ComputeJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ANALYTICS"])
        :analytics
      else
        :low_priority
      end
    end

    retry_on ActiveRecord::ActiveRecordError, wait: :polynomially_longer, attempts: 6

    def perform(subscription, timestamp:)
      DailyUsages::ComputeService.call(subscription:, timestamp:).raise_if_error!
    end
  end
end
