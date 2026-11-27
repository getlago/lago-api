# frozen_string_literal: true

module Billing
  Obligation = Data.define(:cycle, :segments, :billing_at, :terms, :termination_billing_at) do
    def initialize(cycle:, segments:, billing_at:, terms:, termination_billing_at: nil)
      super
    end

    def operation_billing_at(after: nil)
      if after && billing_at > after
        termination_billing_at || billing_at
      else
        billing_at
      end
    end

    # Coverage starts when a rate first applies within this obligation. If the cycle starts
    # on January 1 but the first rate takes effect on January 5, coverage starts on January 5.
    def coverage_started_at = segments.first.started_at

    def coverage_ended_at = segments.last.ended_at

    def cycle_coverage_window = coverage_started_at...coverage_ended_at

    def starts_on_or_after?(timestamp)
      coverage_started_at >= timestamp
    end

    def pricing_inputs_for(segment)
      {
        rate_card_rate: segment.rate, rate_override: cycle.phase.rate_override,
        started_at: segment.started_at, ended_at: segment.ended_at, cycle_started_at: cycle.started_at,
        billing_at: terms.pricing_anchor_for(segment), proration_ratio: proration_ratio_for(segment)
      }
    end

    def proration_ratio_for(segment)
      if terms.prorated
        cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)
      else
        1.0
      end
    end
  end
end
