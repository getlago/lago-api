# frozen_string_literal: true

module BillingOperations
  class ResolveSegmentsService < BaseService
    Result = BaseResult[:segments, :schedule, :planned_operation, :next_planned_operation]

    def initialize(operation:)
      @operation = operation
      super
    end

    def call
      return result.single_validation_failure!(field: :operation, error_code: "fixed_advance_reconciliation_unsupported") if
        operation.action_type == "reconcile_advance_coverage"

      result.schedule = BuildScheduleService.call!(
        contract_rate_card: operation.contract_rate_card
      ).schedule
      result.planned_operation = find_planned_operation(result.schedule)
      result.next_planned_operation = next_planned_operation(result.schedule, result.planned_operation)
      result.segments = result.planned_operation&.billable_segments&.map { build_billing_segment(it) } || []
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation

    def find_planned_operation(schedule)
      return unless operation.action_type

      cycle = schedule.cycle_at(operation.target_cycle_started_at)
      return unless cycle

      planned_operations = schedule.planned_operations_for_cycle(cycle, action_type: operation.action_type)
      return planned_operations.last if operation.causation_type == "contract_termination"

      planned_operations.find { it.billing_at == operation.billing_at }
    end

    def next_planned_operation(schedule, planned_operation)
      return unless planned_operation
      return if operation.causation_type == "contract_termination"

      schedule.next_planned_operation(planned_operation:, action_type: operation.action_type)
    end

    def build_billing_segment(billable_segment)
      segment = BillingSegments::BuildEventSegmentService.call!(
        contract_rate_card: operation.contract_rate_card, billable_segment:
      ).billing_segment
      segment.billing_at = operation.billing_at
      segment
    end
  end
end
