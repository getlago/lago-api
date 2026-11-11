# frozen_string_literal: true

module BillingOperations
  class Schedule < Billing::RateCards::Schedule
    PlannedOperation = Data.define(:cycle_started_at, :billing_at, :billable_segments)

    # Keep separately due slices as separate obligations, in chronological order.
    def planned_operations_for_cycle(cycle, action_type:)
      segments = billable_segments_for_cycle(cycle)
      groups = if action_type == "regroup_paid_fees"
        segments.group_by(&:ended_at)
      else
        segments.group_by(&:billing_at)
      end

      groups.sort_by(&:first).map do |billing_at, billable_segments|
        PlannedOperation.new(cycle_started_at: cycle.started_at, billing_at:, billable_segments:)
      end
    end

    # A cycle can contain multiple independently due slices before the next cycle begins.
    def next_planned_operation(planned_operation:, action_type:)
      cycle = cycle_at(planned_operation.cycle_started_at)
      same_cycle_successor = planned_operations_for_cycle(cycle, action_type:).find do |candidate|
        candidate.billing_at > planned_operation.billing_at
      end

      if same_cycle_successor
        same_cycle_successor
      else
        cycle = next_billable_cycle(after_cycle_started_at: planned_operation.cycle_started_at)
        planned_operations_for_cycle(cycle, action_type:).first if cycle
      end
    end
  end
end
