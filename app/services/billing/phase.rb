# frozen_string_literal: true

module Billing
  # A stretch of consecutive cycles priced under one override.
  #
  # @param billing_interval_cycle_count [Integer, nil] nil runs to the end of the card
  # @param code [String, nil] carried onto every segment the phase prices, so the consumer
  #   reads the attribution off the row instead of resolving the phases again
  #
  # Carries no dates: a phase starts where the previous one ended, so its place in the queue
  # is its date.
  #
  # @example a 3-cycle weekly intro, then the card's own cadence
  #   [Phase(code: "intro", count: 3, rate_override: weekly), Phase.default]
  Phase = Data.define(:code, :billing_interval_cycle_count, :rate_override) do
    # The card's own rate and cadence, with no cycle limit.
    #
    # @return [Phase] no code, because nothing persisted it — being last is what defines it
    def self.default = new(code: nil, billing_interval_cycle_count: nil, rate_override: nil)

    def initialize(code:, billing_interval_cycle_count:, rate_override:)
      if invalid_length?(billing_interval_cycle_count)
        raise ArgumentError, "a phase lasts a positive whole number of cycles, or nil to run " \
          "to the end, got #{billing_interval_cycle_count.inspect}"
      end

      super
    end

    # @return [Boolean] whether this phase runs to the end of the card. Only the last one may.
    def unbounded? = billing_interval_cycle_count.nil?

    private

    def invalid_length?(count)
      return false if count.nil?

      !count.is_a?(Integer) || !count.positive?
    end
  end
end
