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

        schedule.segments_due_by(operation.billing_at).select do |segment|
          next false unless segment.cycle_started_at == result.cycle.started_at

          due_at = billing_at_for(segment, action_type: operation.action_type)
          (after.nil? || due_at > after) && due_at <= operation.billing_at
        end
      end

      def build_planned_operation
        return unless schedule && timestamp

        cycle = schedule.cycle_at(timestamp)

        while cycle
          schedule.segments_due_by(cycle.ended_at).each do |segment|
            next unless segment.cycle_started_at == cycle.started_at

            billing_at = billing_at_for(
              segment,
              action_type: contract_rate_card.periodic_billing_action
            )

            if after
              billing_at = terminal_billing_at(billing_at)
              next if billing_at <= after
            elsif segment.ended_at <= timestamp && billing_at != timestamp
              next
            end

            result.cycle = cycle
            return PlannedOperation.new(
              cycle_started_at: segment.cycle_started_at,
              billing_at:
            )
          end

          cycle = schedule.next_billable_cycle(after_cycle_started_at: cycle.started_at)
        end
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
