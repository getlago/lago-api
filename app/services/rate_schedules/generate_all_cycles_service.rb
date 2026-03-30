# frozen_string_literal: true

module RateSchedules
  class GenerateAllCyclesService < BaseService
    Result = BaseResult

    def initialize(organization:)
      @organization = organization

      super
    end

    def call
      organization.subscription_rate_schedules
        .active
        .where.not(started_at: nil)
        .includes(:rate_schedule, :cycles, subscription: :customer)
        .find_each do |srs|
          next if has_enough_cycles?(srs)

          RateSchedules::GenerateCyclesService.call!(subscription_rate_schedule: srs)
        end

      result
    end

    private

    attr_reader :organization

    def has_enough_cycles?(srs)
      unbilled_count = srs.cycles
        .where.not(id: Fee.where.not(subscription_rate_schedule_cycle_id: nil).select(:subscription_rate_schedule_cycle_id))
        .count

      unbilled_count >= RateSchedules::GenerateCyclesService::CYCLES_AHEAD
    end
  end
end
