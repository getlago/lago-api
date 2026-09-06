# frozen_string_literal: true

module Billing
  # When a schedule bills, and whether a partial cycle is charged for the part it covers.
  # Constant for the whole schedule: a rate card does not change its mind halfway through.
  class Terms < Data.define(:timing, :prorated)
    TIMINGS = %i[advance arrears].freeze

    def initialize(timing:, prorated:)
      timing = timing.to_sym if timing.respond_to?(:to_sym)

      raise ArgumentError, "unknown billing timing #{timing.inspect}, expected one of #{TIMINGS.join(", ")}" unless TIMINGS.include?(timing)
      raise ArgumentError, "prorated must be true or false, got #{prorated.inspect}" unless [true, false].include?(prorated)

      super
    end
  end
end
