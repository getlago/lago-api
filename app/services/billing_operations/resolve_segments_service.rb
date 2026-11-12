# frozen_string_literal: true

module BillingOperations
  # Resolves the slices an operation bills: those of its target cycle that fall due after the
  # previous operation of that cycle and no later than its own billing date.
  class ResolveSegmentsService < BaseService
    Result = BaseResult[:segments, :schedule, :cycle]

    def initialize(operation:)
      @operation = operation
      super
    end

    def call
      if operation.action_type == "reconcile_advance_coverage"
        unless operation.causation_type == "rate_change" && operation.contract_rate_card.periodic_billing_action == "renew_fixed_advance"
          return result.single_validation_failure!(field: :operation, error_code: "fixed_advance_reconciliation_unsupported")
        end

        # Price changes do not repurchase advance coverage or adjust an existing fee.
        result.segments = []
        return result
      end

      result.schedule = BuildScheduleService.call!(contract_rate_card: operation.contract_rate_card).schedule
      result.cycle = result.schedule.cycle_at(operation.target_cycle_started_at) if operation.action_type
      result.segments = owned_billable_segments.map { build_billing_segment(it) }
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation

    def owned_billable_segments
      return [] unless result.cycle

      after = previous_billing_at

      result.schedule.billable_segments_for_cycle(result.cycle).select do |billable_segment|
        due_at = result.schedule.due_at(billable_segment, action_type: operation.action_type)

        (after.nil? || due_at > after) && due_at <= operation.billing_at
      end
    end

    # An earlier operation of the cycle keeps its slices even when it failed, so a retry
    # cannot bill them twice.
    def previous_billing_at
      operation.contract_rate_card.billing_operations
        .where(
          organization_id: operation.organization_id,
          cancelled_at: nil,
          action_type: operation.action_type,
          target_cycle_started_at: operation.target_cycle_started_at,
          billing_at: ...operation.billing_at
        )
        .maximum(:billing_at)
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
