# frozen_string_literal: true

module Billing
  # A slice of a cycle priced by one rate. A cycle with no rate change inside it has
  # exactly one segment, covering the whole cycle.
  #
  # Half-open like every window in the engine: `ended_at` is the first instant it does not
  # cover, so consecutive segments share an instant.
  Segment = Data.define(:started_at, :ended_at, :rate)
end
