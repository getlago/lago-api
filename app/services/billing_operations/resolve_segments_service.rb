# frozen_string_literal: true

module BillingOperations
  # Resolves a persisted operation's slices in its stored cycle without changing its identity.
  class ResolveSegmentsService < BaseService
    Result = BaseResult[:segments, :schedule, :cycle]

    def initialize(operation:, pricing_units_by_code: nil, units_histories: {})
      @operation = operation
      @pricing_units_by_code = pricing_units_by_code
      @units_histories = units_histories
      super
    end

    def call
      if operation.processed_at && operation.segments.any? { !it.units.nil? }
        result.segments = operation.segments.map { restore_segment(it) }
        return result
      end

      if operation.units_change? && !operation.contract_rate_card.needs_reconciliation?
        result.segments = []
        return result
      end

      if operation.action_type == "reconcile_advance_coverage" && !operation.units_change?
        unless operation.reason == "rate_change" && operation.contract_rate_card.needs_reconciliation?
          return result.single_validation_failure!(field: :operation, error_code: "fixed_advance_reconciliation_unsupported")
        end

        # Price changes do not repurchase advance coverage or adjust an existing fee.
        result.segments = []
        return result
      end

      schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: operation.contract_rate_card).schedule
      result.schedule = schedule
      result.cycle = schedule.cycle_at(operation.target_cycle_started_at)
      billable_segments = if operation.units_change?
        [schedule.segment_covering(operation.billing_at)].compact
      else
        owned_billable_segments(after: previous_billing_at)
      end
      segments = billable_segments.map { build_billing_segment(it) }
      result.segments = ResolveFixedUnitsService.call!(segments:, cycle: result.cycle, operation:, units_histories:).segments
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation, :pricing_units_by_code, :units_histories

    def restore_segment(segment)
      card = operation.contract_rate_card
      BillingSegment.new(
        organization: card.organization, customer: card.contract.customer, contract: card.contract,
        contract_rate_card: card, rate_card_rate: segment.rate_card_rate, rate_override: segment.rate_override,
        pricing_unit: segment.pricing_unit, rate_properties: segment.rate_properties, currency: segment.currency,
        started_at: segment.started_at, ended_at: BillingSegment.inclusive_end(segment.ended_at),
        cycle_started_at: operation.target_cycle_started_at, billing_at: operation.billing_at,
        proration_ratio: segment.proration_ratio, units: segment.units, prepaid_units: segment.prepaid_units,
        units_intervals: segment.units_intervals
      )
    end

    # An operation whose cycle the schedule no longer has bills nothing.
    def owned_billable_segments(after:)
      cycle = result.cycle

      if cycle
        result.schedule.segments_due_in_cycle(cycle.started_at, by: operation.billing_at, after:)
      else
        []
      end
    end

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
        contract_rate_card: operation.contract_rate_card, billable_segment:, pricing_units_by_code:
      ).billing_segment
      segment.billing_at = operation.billing_at
      segment
    end
  end
end
