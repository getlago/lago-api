# frozen_string_literal: true

module BillingOperations
  class Schedule < Billing::RateCards::Schedule
    PlannedOperation = Data.define(:cycle_started_at, :billing_at)

    def initialize(final_billing_at: nil, **attributes)
      @final_billing_at = final_billing_at
      @ends_at = attributes[:ends_at]
      super(**attributes)
    end

    # The first date due after an instant: in this cycle, or else the first one of the next
    # billable cycle. A price change inside a cycle makes its slices due on separate dates.
    def next_planned_operation(cycle, action_type:, after: nil)
      while cycle
        billing_at = billing_dates_for_cycle(cycle, action_type:).find { after.nil? || it > after }
        if billing_at == @ends_at && @final_billing_at
          billing_at = @final_billing_at
        end
        return PlannedOperation.new(cycle_started_at: cycle.started_at, billing_at:) if billing_at

        cycle = next_billable_cycle(after_cycle_started_at: cycle.started_at)
        after = nil
      end
    end

    def billing_dates_for_cycle(cycle, action_type:)
      billable_segments_for_cycle(cycle).map { due_at(it, action_type:) }.uniq.sort
    end

    # Paid fees are regrouped once their service ends, whatever the billing timing.
    def due_at(billable_segment, action_type:)
      if action_type == "regroup_paid_fees"
        billable_segment.ended_at
      else
        billable_segment.billing_at
      end
    end
  end
end
