# frozen_string_literal: true

module Billing
  Obligation = Data.define(:cycle, :segments, :billing_at, :terms) do
    def proration_ratio_for(segment)
      if terms.prorated
        cycle.calendar.proration_ratio(segment.started_at, segment.ended_at)
      else
        1.0
      end
    end
  end
end
