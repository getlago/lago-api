# frozen_string_literal: true

module Billing
  class Terms < Data.define(:timing, :prorated, :billing_scope, :due_on_coverage_end)
    TIMINGS = %i[advance arrears].freeze

    def initialize(timing:, prorated:, billing_scope: ContractRateCard::BILLING_SCOPES.fetch(:cycle), due_on_coverage_end: false)
      timing = timing.to_sym if timing.respond_to?(:to_sym)
      billing_scope = ContractRateCard::BILLING_SCOPES.fetch(billing_scope, billing_scope)

      raise ArgumentError, "unknown billing timing #{timing.inspect}, expected one of #{TIMINGS.join(", ")}" unless TIMINGS.include?(timing)
      raise ArgumentError, "prorated must be true or false, got #{prorated.inspect}" unless [true, false].include?(prorated)
      unless ContractRateCard::BILLING_SCOPES.value?(billing_scope)
        raise ArgumentError, "unknown billing scope #{billing_scope.inspect}"
      end
      unless [true, false].include?(due_on_coverage_end)
        raise ArgumentError, "due_on_coverage_end must be true or false, got #{due_on_coverage_end.inspect}"
      end

      super
    end

    def cycle_scope?
      billing_scope == ContractRateCard::BILLING_SCOPES.fetch(:cycle)
    end

    # Grouping moves the obligation, not the slice-based pricing anchor below.
    def obligation_billing_at_for(cycle:, segments:)
      window = cycle_scope? ? cycle : segments.sole
      if due_on_coverage_end || timing == :arrears
        window.ended_at
      else
        segments.first.started_at
      end
    end

    # Which end of a window the pricing terms use as their anchor.
    #
    # @param window [#started_at, #ended_at] a cycle, or a slice of one
    # @return [Time] the start in advance, the end in arrears
    def pricing_anchor_for(window)
      if timing == :advance
        window.started_at
      else
        window.ended_at
      end
    end
  end
end
