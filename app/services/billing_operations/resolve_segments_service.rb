# frozen_string_literal: true

module BillingOperations
  # Resolves a persisted operation's slices in its stored cycle without changing its identity.
  class ResolveSegmentsService < BaseService
    Result = BaseResult[:billing_segments]

    def initialize(operation:, pricing_units_by_code: nil)
      @operation = operation
      @pricing_units_by_code = pricing_units_by_code
      super
    end

    def call
      result.billing_segments = operation.segments.map do |row|
        BillingSegments::BuildService.call!(
          contract_rate_card: operation.contract_rate_card, rate_card_rate: row.rate_card_rate, rate_override: row.rate_override,
          started_at: row.started_at, ended_at: row.ended_at, cycle_started_at: operation.target_cycle_started_at,
          billing_at: operation.billing_at, proration_ratio: row.proration_ratio, pricing_units_by_code:
        ).billing_segment
      end
      result
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :operation, :pricing_units_by_code
  end
end
