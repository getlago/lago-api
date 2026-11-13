# frozen_string_literal: true

module BillingOperations
  module Schedule
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation, :cycle, :schedule, :billable_segments]
      PlannedOperation = Data.define(:cycle_started_at, :billing_at)

      def initialize(
        contract_rate_card:,
        timestamp:,
        schedule: contract_rate_card && Billing::RateCards::BuildScheduleService.call!(contract_rate_card:).schedule,
        after: nil,
        operation: nil
      )
        @contract_rate_card = contract_rate_card
        @schedule = schedule
        @timestamp = timestamp
        @after = after
        @operation = operation
        super
      end

      def call
        return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card

        result.schedule = schedule
        if operation
          result.cycle = schedule&.cycle_at(operation.target_cycle_started_at)
          result.billable_segments = owned_billable_segments
        else
          result.planned_operation = build_planned_operation
        end
        result
      end

      private

      attr_reader :contract_rate_card, :schedule, :timestamp, :after, :operation

      def owned_billable_segments
        return [] unless schedule && result.cycle

        schedule.segments(from: resumed(result.cycle.started_at))
          .take_while { it.cycle_started_at == result.cycle.started_at }
          .select do |segment|
            due_at = billing_at_for(segment, action_type: operation.action_type)
            (after.nil? || due_at > after) && due_at <= operation.billing_at
          end
          .to_a
      end

      def build_planned_operation
        return unless schedule && timestamp

        from = resumed(timestamp)
        segment = if after
          schedule.next_obligation(after:, from:) { planned_billing_at(it) }
        else
          schedule.first_obligation(at: timestamp, from:) { planned_billing_at(it) }
        end

        if segment
          result.cycle = schedule.cycle_at(segment.cycle_started_at)
          PlannedOperation.new(cycle_started_at: segment.cycle_started_at, billing_at: planned_billing_at(segment))
        end
      end

      # A resumed schedule never plans before its resume point.
      def resumed(timestamp)
        [timestamp, schedule.resume_at].compact.max
      end

      # A billing after a completed one can fall on the contract's end, which a termination moves.
      def planned_billing_at(segment)
        billing_at = billing_at_for(segment, action_type: contract_rate_card.periodic_billing_action)

        after ? terminal_billing_at(billing_at) : billing_at
      end

      def billing_at_for(segment, action_type:)
        if action_type == BillingOperation::ACTION_TYPES.fetch(:regroup_paid_fees)
          segment.ended_at
        else
          segment.billing_at
        end
      end

      def terminal_billing_at(billing_at)
        contract = contract_rate_card.contract

        if contract.terminated_at && billing_at == contract.billing_ends_at
          contract.terminated_at
        else
          billing_at
        end
      end
    end
  end
end
