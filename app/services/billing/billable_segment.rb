# frozen_string_literal: true

module Billing
  # One slice of one cycle — everything a writer needs for one `billing_segments` row.
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
  )
end
