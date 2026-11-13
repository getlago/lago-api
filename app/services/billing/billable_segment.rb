# frozen_string_literal: true

module Billing
  # One priced slice of a cycle, used to build an in-memory billing segment.
  #
  # A slice carries two instants that usually match:
  # - `billing_at` is where the card's terms place it: its start in advance, its end in arrears.
  # - `due_at` is when a periodic operation picks it up. It differs for cards that regroup paid
  #   advance fees: usage events bill them as they arrive, and the periodic operation only
  #   gathers them once coverage ends, so the slice falls due at `ended_at`.
  #
  # @example a monthly cycle cut by a rate change on Feb 15, in arrears
  #   [Segment(Feb 1 -> Feb 15, billing_at Feb 15), Segment(Feb 15 -> Mar 1, billing_at Mar 1)]
  BillableSegment = Data.define(
    :cycle_index,
    :cycle_started_at,
    :started_at,
    :ended_at,
    :billing_at,
    :rate,
    :rate_override,
    :proration_ratio,
    :rate_phase_code,
    :due_at
  ) do
    # The calendar only builds a segment for a window it can price, so a segment without
    # either is a caller's mistake rather than a state to carry. Same guard as Terms and
    # Phase: the invariant belongs where the value is made, not where it is read.
    def initialize(rate:, rate_override:, due_at: nil, **attributes)
      if rate.nil? && rate_override.nil?
        raise ArgumentError, "a billable segment needs a rate or an override to price it"
      end

      # Without a due instant of its own, a slice falls due when its terms bill it.
      super(**attributes, rate:, rate_override:, due_at: due_at || attributes[:billing_at])
    end

    # A phase override prices the segment; the rate card's own rate does otherwise.
    def properties = (rate_override || rate).properties
  end
end
