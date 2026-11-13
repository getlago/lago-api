# frozen_string_literal: true

module BillingOperations
  # Resolves a persisted operation's slices in its stored cycle without changing its identity.
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

      resume_at = previous_billing_at
      schedule = Billing::RateCards::BuildScheduleService.call!(
        contract_rate_card: operation.contract_rate_card,
        resume_at: resume_at || operation.target_cycle_started_at
      ).schedule
      plan_result = Schedule::BuildPlannedOperation.call!(
        contract_rate_card: operation.contract_rate_card,
        timestamp: operation.target_cycle_started_at,
        schedule:,
        after: resume_at,
        operation:
      )
      result.schedule = plan_result.schedule
      result.cycle = plan_result.cycle
      result.segments = plan_result.billable_segments.map { build_billing_segment(it) }
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation

    # Only completed billing owns coverage; a failed run leaves its cursor unchanged.
    def previous_billing_at
      operation.contract_rate_card.billing_operations
        .completed
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
