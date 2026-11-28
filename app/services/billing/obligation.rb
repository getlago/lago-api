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

    def selectable_from?(timestamp, after: nil)
      if after
        operation_billing_at(after:) > after
      else
        segments.last.ended_at > timestamp || billing_at == timestamp
      end
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
