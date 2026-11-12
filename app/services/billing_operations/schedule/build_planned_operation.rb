# frozen_string_literal: true

module BillingOperations
  class Schedule
    class BuildPlannedOperation < BaseService
      Result = BaseResult[:planned_operation, :cycle, :schedule]

      def initialize(
        contract_rate_card:,
        timestamp:,
        schedule: contract_rate_card && BillingOperations::BuildScheduleService.call!(contract_rate_card:).schedule,
        after: nil
      )
        @contract_rate_card = contract_rate_card
        @schedule = schedule
        @timestamp = timestamp
        @after = after
        super
      end

      def call
        return result.not_found_failure!(resource: "contract_rate_card") unless contract_rate_card

        result.schedule = schedule
        result.planned_operation = build_planned_operation
        result
      end

      private

      attr_reader :contract_rate_card, :schedule, :timestamp, :after

      def build_planned_operation
        return unless schedule && timestamp

        cycle = schedule.cycle_at(timestamp)

        while cycle
          schedule.billable_segments_for_cycle(cycle).each do |segment|
            next if !after && segment.ended_at <= timestamp

            plan = planned_operation(segment)
            next if after && plan.billing_at <= after

            result.cycle = cycle
            return plan
          end

          cycle = schedule.next_billable_cycle(after_cycle_started_at: cycle.started_at)
        end
      end

      def planned_operation(segment)
        billing_at = if contract_rate_card.periodic_billing_action == BillingOperation::ACTION_TYPES.fetch(:regroup_paid_fees)
          segment.ended_at
        else
          segment.billing_at
        end

        billing_at = terminal_billing_at(billing_at) if after

        BillingOperations::Schedule::PlannedOperation.new(
          cycle_started_at: segment.cycle_started_at,
          billing_at:
        )
      end

      def terminal_billing_at(billing_at)
        contract = contract_rate_card.contract
        natural_end = [contract.ended_at, contract.terminated_at].compact.min

        if contract.terminated_at && billing_at == natural_end
          contract.terminated_at
        else
          billing_at
        end
      end
    end
  end
end
