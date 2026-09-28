# frozen_string_literal: true

module Billing
  # One billing period of one rate card.
  #
  # @param ended_at [Time] EXCLUSIVE, unlike the column of the same name
  # @param calendar [Calendar] the ruler this cycle was measured on; it varies per cycle,
  #   because a cadence change re-anchors mid-walk
  #
  # @example a monthly card anchored Jan 1, cut short by a weekly intro phase
  #   Cycle(index: 0, started_at: Jan 15, ended_at: Jan 22, phase: "intro", calendar: ...)
  Cycle = Data.define(:index, :started_at, :ended_at, :phase, :calendar)
end
