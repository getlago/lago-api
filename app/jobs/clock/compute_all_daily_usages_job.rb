# frozen_string_literal: true

module Clock
  class ComputeAllDailyUsagesJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    def perform
      DailyUsages::ComputeAllService.call
    end
  end
end
