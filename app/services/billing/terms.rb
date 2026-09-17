# frozen_string_literal: true

module Billing
  class Terms < Data.define(:timing, :prorated)
    TIMINGS = %i[advance arrears].freeze

    def initialize(timing:, prorated:)
      timing = timing.to_sym if timing.respond_to?(:to_sym)

      raise ArgumentError, "unknown billing timing #{timing.inspect}, expected one of #{TIMINGS.join(", ")}" unless TIMINGS.include?(timing)
      raise ArgumentError, "prorated must be true or false, got #{prorated.inspect}" unless [true, false].include?(prorated)

      super
    end

    # Which end of a window falls due.
    #
    # @param window [#started_at, #ended_at] a cycle, or a slice of one
    # @return [Time] the start in advance, the end in arrears
    def billing_at_for(window)
      if timing == :advance
        window.started_at
      else
        window.ended_at
      end
    end
  end
end
