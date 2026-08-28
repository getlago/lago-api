# frozen_string_literal: true

module BillingPeriods
  # When a period is billed — the only thing separating paying up front from paying after the
  # fact, and the short form of the card's `billing_timing`.
  #
  # Arrears is advance shifted by one period. A run on Mar 1 bills March if the card pays in
  # advance and February if it pays in arrears: both bill ON a boundary, and only which boundary
  # differs.
  #
  # "The day after it closes", which is how arrears is usually described, is the same moment as
  # the next boundary: a period closes at 23:59:59.999 and the next opens at the following
  # midnight. Reaching it by position rather than by adding a day to the close is what keeps it
  # right for a customer who does not live in UTC.
  class Timing
    TIMINGS = %i[advance arrears].freeze

    def initialize(billing_timing)
      @billing_timing = billing_timing.to_sym

      return if TIMINGS.include?(@billing_timing)

      raise ArgumentError, "Invalid billing timing: #{billing_timing}"
    end

    def advance?
      billing_timing == :advance
    end

    # The moment a run bills the period at this position: the boundary it opens on when the card
    # pays up front, the next one along when it pays after the fact. One step apart, and that
    # step is the whole difference between the two.
    def billed_at(boundaries, position)
      advance? ? boundaries.at(position).utc : boundaries.at(position + 1).utc
    end

    # Where the card's clock points once that period has been billed — which is simply when the
    # NEXT period falls due, whichever way the card pays.
    def next_billing_at(boundaries, position)
      billed_at(boundaries, position + 1)
    end

    # Where a card's clock starts, asked once when the card is created.
    #
    # `[started_at, now].max` is the one piece of policy here: a card backdated six months bills
    # the period it is in, not the six it missed. It matters because the producer opens its
    # range at `min(next_billing_at, now)` — a clock seeded at the first period would make that
    # range six months wide. Billing history is still reachable by moving the clock back on
    # purpose, which leaves a date on the row instead of a flag nobody remembers.
    #
    # The trailing max is what bills an advance card joining mid-period ON THE DAY IT JOINS. In
    # arrears the billing date is already past the start, so it does nothing.
    def first_billing_at(boundaries, started_at, now: Time.current)
      opens_at = started_at.in_time_zone(boundaries.timezone).beginning_of_day
      position = boundaries.position_on_or_before([started_at, now].max)

      [billed_at(boundaries, position), opens_at.utc].max
    end

    private

    attr_reader :billing_timing
  end
end
