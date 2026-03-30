# frozen_string_literal: true

module RateSchedules
  class ActivateService < BaseService
    Result = BaseResult

    def initialize(timestamp: Time.current)
      @timestamp = timestamp

      super
    end

    def call
      SubscriptionRateSchedule
        .active
        .where.not(intervals_to_bill: nil)
        .where.not(started_at: nil)
        .includes(:rate_schedule, subscription: :customer)
        .find_each do |srs|
          next unless srs.end_date && srs.end_date <= timestamp.to_date

          # Always activate the next pending SRS on date, regardless of billing state.
          # phase transitions are date-based and independent of payment/billing success.
          activate_next(srs)

          # Only terminate the exhausted SRS when all its cycles have been billed.
          # This allows the billing service to retry missed cycles even after the
          # successor is already active.
          terminate(srs) if srs.exhausted?
        end

      result
    end

    private

    attr_reader :timestamp

    def activate_next(exhausted_srs)
      current_position = exhausted_srs.rate_schedule.position

      next_srs = exhausted_srs.subscription.subscription_rate_schedules
        .where(product_item_id: exhausted_srs.product_item_id)
        .joins(:rate_schedule)
        .where("rate_schedules.position > ?", current_position)
        .order("rate_schedules.position ASC")
        .first

      return unless next_srs
      return unless next_srs.pending?

      next_srs.update!(status: :active, started_at: timestamp)
      next_srs.update_next_billing_date!
    end

    def terminate(srs)
      srs.update!(status: :terminated, ended_at: timestamp)
    end
  end
end