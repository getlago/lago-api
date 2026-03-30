# frozen_string_literal: true

module RateSchedules
  class GenerateCyclesService < BaseService
    Result = BaseResult

    CYCLES_AHEAD = 2

    def initialize(subscription_rate_schedule:)
      @subscription_rate_schedule = subscription_rate_schedule

      super
    end

    def call
      return result if subscription_rate_schedule.started_at.nil?

      last_cycle = subscription_rate_schedule.cycles.order(cycle_index: :desc).first
      next_index = last_cycle ? last_cycle.cycle_index + 1 : 0
      target_index = next_index + CYCLES_AHEAD - 1

      (next_index..target_index).each do |index|
        from_date = subscription_rate_schedule.send(:billing_date_for, index)
        to_date = subscription_rate_schedule.send(:billing_date_for, index + 1)

        break if cycle_limit_reached?(index)

        subscription_rate_schedule.cycles.create!(
          organization: subscription_rate_schedule.organization,
          cycle_index: index,
          from_datetime: from_date.to_datetime,
          to_datetime: to_date.to_datetime
        )
      end

      result
    end

    private

    attr_reader :subscription_rate_schedule

    def cycle_limit_reached?(index)
      limit = subscription_rate_schedule.rate_schedule.billing_cycle_count
      return false if limit.nil?

      index >= limit
    end
  end
end
