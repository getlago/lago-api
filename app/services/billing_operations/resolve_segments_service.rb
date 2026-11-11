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

      schedule = BuildScheduleService.call!(
        contract_rate_card: operation.contract_rate_card
      ).schedule
      resolution = ResolvePlannedOperationService.call!(
        operation:, schedule:
      )
      planned_operation = resolution.planned_operation
      slices = planned_operation&.billable_segments || []

      result.schedule = schedule
      result.planned_operation = planned_operation
      result.next_planned_operation = resolution.next_planned_operation
      result.segments = slices.map do |slice|
        BillingSegments::BuildEventSegmentService.call!(
          contract_rate_card: operation.contract_rate_card, billable_segment: slice
        ).billing_segment.tap do |segment|
          segment.billing_at = operation.billing_at
        end
      end
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation
  end
end
