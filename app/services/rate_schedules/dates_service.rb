# frozen_string_literal: true

module RateSchedules
  # Given a SubscriptionRateSchedule + billing_at timestamp, resolves which
  # cycle is being billed. Returns the cycle_index and its boundaries.
  #
  # Minimal version: anniversary billing, arrears only.
  # TODO: pay_in_advance, billing_anchor_date, customer timezone, ended_at cap, current_usage flag
  class DatesService
    def initialize(subscription_rate_schedule:, billing_at:)
      @srs = subscription_rate_schedule
      @billing_at = billing_at
    end

    def cycle_index
      periods_from(srs.started_at, billing_at) - 1
    end

    def from_datetime
      period_start_for(cycle_index)
    end

    def to_datetime
      period_start_for(cycle_index + 1)
    end

    private

    attr_reader :srs, :billing_at

    def period_start_for(index)
      return srs.started_at if index.zero?

      advance(srs.started_at, index)
    end

    def periods_from(base, target)
      rs = srs.rate_schedule
      count = rs.billing_interval_count

      case rs.billing_interval_unit
      when "day" then (target.to_date - base.to_date).to_i / count
      when "week" then (target.to_date - base.to_date).to_i / 7 / count
      when "month"
        months = (target.year - base.year) * 12 + (target.month - base.month)
        months / count
      when "year"
        (target.year - base.year) / count
      end
    end

    def advance(date, n)
      rs = srs.rate_schedule
      offset = n * rs.billing_interval_count

      case rs.billing_interval_unit
      when "day" then date + offset.days
      when "week" then date + offset.weeks
      when "month" then date + offset.months
      when "year" then date + offset.years
      end
    end
  end
end
