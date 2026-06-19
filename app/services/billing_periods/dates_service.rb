# frozen_string_literal: true

module BillingPeriods
  # Computes the boundaries of a billing period and the next billing instant for a
  # single subscription product item, from its anchor and the active rate's interval.
  #
  # All math is done in the customer timezone, then converted to UTC so the billing
  # pickup can stay a plain UTC scan on `next_billing_at`.
  #
  # Boundaries are always re-derived from the anchor (anchor + n * interval) rather
  # than incremented from the previous period, so monthly/yearly anchoring never
  # drifts (e.g. Jan 31 -> Feb 28 -> Mar 31, not Mar 28).
  class DatesService < BaseService
    Result = BaseResult[:period_from, :period_to, :next_billing_at]

    def initialize(billing_anchor_date:, interval_count:, interval_unit:, billing_timing:, timezone:, period_started_at: nil)
      @billing_anchor_date = billing_anchor_date
      @interval_count = interval_count
      @interval_unit = interval_unit.to_sym
      @billing_timing = billing_timing.to_sym
      @timezone = timezone
      @period_started_at = period_started_at
      super
    end

    def call
      result.period_from = period_from.utc
      result.period_to = period_to.utc
      result.next_billing_at = (advance? ? period_from : period_to).utc
      result
    end

    private

    attr_reader :billing_anchor_date, :interval_count, :interval_unit, :billing_timing, :timezone, :period_started_at

    def advance?
      billing_timing == :advance
    end

    # Start of the period being described. Defaults to the anchor (the first period).
    def period_from
      @period_from ||= (period_started_at&.in_time_zone(timezone) || anchor_at)
    end

    # The first boundary strictly after period_from, re-derived from the anchor.
    def period_to
      @period_to ||= begin
        nth = index_of(period_from) + 1
        boundary = boundary_at(nth)
        boundary = boundary_at(nth += 1) while boundary <= period_from
        boundary
      end
    end

    # Beginning of the anchor day in the customer timezone.
    def anchor_at
      @anchor_at ||= billing_anchor_date.in_time_zone(timezone).beginning_of_day
    end

    # The nth period boundary: anchor advanced by n intervals. Computed from the
    # anchor every time so month-end anchoring does not drift across periods.
    def boundary_at(nth)
      step = nth * interval_count

      case interval_unit
      when :day then anchor_at + step.days
      when :week then anchor_at + step.weeks
      when :month then anchor_at + step.months
      when :year then anchor_at + step.years
      end
    end

    # How many whole intervals a datetime sits past the anchor.
    def index_of(datetime)
      elapsed = case interval_unit
      when :day then (datetime.to_date - anchor_at.to_date).to_i
      when :week then (datetime.to_date - anchor_at.to_date).to_i / 7
      when :month then ((datetime.year - anchor_at.year) * 12) + (datetime.month - anchor_at.month)
      when :year then datetime.year - anchor_at.year
      end

      elapsed / interval_count
    end
  end
end
