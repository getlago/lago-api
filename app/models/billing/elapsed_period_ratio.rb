# frozen_string_literal: true

module Billing
  module ElapsedPeriodRatio
    # Inclusive-day progress for usage projection, not service-price proration.
    # Callers choose the calendar dates and may supply a full-period denominator
    # for a shortened service window. The last service day always completes it.
    def self.calculate(from_date:, to_date:, current_date:, duration_in_days: nil)
      if current_date >= to_date
        1.0
      elsif current_date < from_date
        0.0
      else
        duration = duration_in_days || (to_date - from_date).to_i + 1
        days_passed = (current_date - from_date).to_i + 1
        days_passed.fdiv(duration).clamp(0.0, 1.0)
      end
    end
  end
end
