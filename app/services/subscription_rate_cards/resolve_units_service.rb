# frozen_string_literal: true

module SubscriptionRateCards
  # The quantity to bill for one window. Units changes version the rate card row rather than
  # editing it, so several versions can overlap a single window; this resolves them into the
  # one number the charge model is applied to.
  #
  # Applying the charge model once to a resolved quantity is what keeps tiered pricing
  # correct: pricing each version separately and adding the results would restart the tiers
  # on every change. Rate changes are different — they split the period upstream, because
  # each segment legitimately carries its own tier table and its own unit price.
  #
  #   prorated     -> time-weighted average across the window
  #   not prorated -> the quantity in force at the end of the window
  #
  # Days are counted by calendar date, so a version that only lived part of a day weighs
  # nothing and the day belongs to whichever version closed it. That keeps a window's weights
  # summing to exactly 1, and stops a same-day change from charging the same day twice.
  class ResolveUnitsService < BaseService
    # units         -> what the amount is computed from
    # closing_units -> the quantity in force when the window closes, which is what the
    #                  invoice line reports. They differ only when prorating: a quantity is
    #                  fractional in time, but a seat is not, so the line shows whole seats
    #                  and the fraction is absorbed into the unit price.
    Result = BaseResult[:units, :closing_units]

    def initialize(subscription_rate_card:, from:, to:, timezone: nil)
      @subscription_rate_card = subscription_rate_card
      @from = from
      @to = to
      @timezone = timezone || subscription_rate_card.customer.applicable_timezone
      super
    end

    def call
      result.units = subscription_rate_card.proration? ? weighted_units : trailing_units
      result.closing_units = trailing_units
      result
    end

    private

    attr_reader :subscription_rate_card, :from, :to, :timezone

    def versions
      @versions ||= subscription_rate_card.card_versions.select { |version| overlaps?(version) }
    end

    def overlaps?(version)
      version.started_at <= to && (version.ended_at.nil? || version.ended_at > from)
    end

    def weighted_units
      total_days = days_between(from, exclusive_end)
      return units_of(versions.last) if total_days.zero?

      versions.sum(BigDecimal(0)) do |version|
        units_of(version) * days_for(version) / total_days
      end
    end

    # Without proration the window is billed at a single quantity, so an intra-period change
    # only matters if it is the one still standing when the window closes.
    def trailing_units
      units_of(versions.last)
    end

    def days_for(version)
      segment_start = [version.started_at, from].max
      segment_end = [version.ended_at || exclusive_end, exclusive_end].min

      days_between(segment_start, segment_end)
    end

    # period_to is inclusive (end of day), so the exclusive boundary is the moment after it.
    def exclusive_end
      @exclusive_end ||= to + 1.second
    end

    # Whole calendar days in the customer timezone — the measure the legacy prorated
    # aggregation uses, and the reason a sub-day version contributes zero.
    def days_between(start_at, end_at)
      return 0 if end_at <= start_at

      (end_at.in_time_zone(timezone).to_date - start_at.in_time_zone(timezone).to_date).to_i
    end

    def units_of(version)
      BigDecimal((version&.units || 0).to_s)
    end
  end
end
