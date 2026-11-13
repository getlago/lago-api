# frozen_string_literal: true

module Billing
  # One priced slice of a cycle, used to build an in-memory billing segment.
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
    :rate_phase_code
  ) do
    # The calendar only builds a segment for a window it can price, so a segment without
    # either is a caller's mistake rather than a state to carry. Same guard as Terms and
    # Phase: the invariant belongs where the value is made, not where it is read.
    def initialize(rate:, rate_override:, **attributes)
      if rate.nil? && rate_override.nil?
        raise ArgumentError, "a billable segment needs a rate or an override to price it"
      end

      super(**attributes, rate:, rate_override:)
    end

    # A phase override prices the segment; the rate card's own rate does otherwise.
    def properties = (rate_override || rate).properties
  end
end
