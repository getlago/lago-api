# frozen_string_literal: true

module BillingOperations
  # Resolves a persisted operation's slices in its stored cycle without changing its identity.
  class ResolveSegmentsService < BaseService
    Result = BaseResult[:billing_segments, :schedule, :obligation]

    def initialize(operation:, pricing_units_by_code: nil)
      @operation = operation
      @pricing_units_by_code = pricing_units_by_code
      super
    end

    def call
      if operation.action_type == "reconcile_advance_coverage"
        unless operation.reason == "rate_change" && operation.contract_rate_card.periodic_billing_action == "renew_fixed_advance"
          return result.single_validation_failure!(field: :operation, error_code: "fixed_advance_reconciliation_unsupported")
        end

        # Price changes do not repurchase advance coverage or adjust an existing fee.
        result.billing_segments = []
        return result
      end

      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: operation.contract_rate_card).schedule
      result.schedule = schedule
      result.obligation = schedule.obligation_for_operation(
        cycle_started_at: operation.target_cycle_started_at,
        billing_at: operation.billing_at,
        after: previous_billing_at
      )
      result.billing_segments = if result.obligation
        result.obligation.segments.map { build_billing_segment(obligation: result.obligation, segment: it) }
      else
        []
      end
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation, :pricing_units_by_code

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

    def build_billing_segment(obligation:, segment:)
      billing_segment = BillingSegments::BuildService.call!(
        contract_rate_card: operation.contract_rate_card, obligation:, segment:, pricing_units_by_code:
      ).billing_segment
      # TODO: Remove BillingSegment#billing_at; make Obligation#billing_at the single source of truth.
      billing_segment.billing_at = operation.billing_at
      billing_segment
    end
  end
end
