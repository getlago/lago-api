# frozen_string_literal: true

module BillingSegments
  class BuildCycleUsageTrackerService < BaseService
    Result = BaseResult[:cycle_usage_tracker]

    def initialize(segments:, obligation:)
      @segments = segments
      @obligation = obligation
      super
    end

    def call
      result.cycle_usage_tracker = EMPTY_CYCLE_USAGE_TRACKER
      return result if segments.empty?

      first = segments.first
      card = first.contract_rate_card
      rate_card = card.rate_card
      return result unless first.organization.product_catalog_enabled? && rate_card.product.metered? && rate_card.arrears?

      metric = rate_card.product.billable_metric
      if metric.weighted_sum_agg? && !metric.recurring? && card.billing_scope_cycle?
        result.cycle_usage_tracker = Fees::ChargeService::Trackers::CycleCarryoverVariation.for(
          segments:, coverage_started_at: obligation.coverage_started_at
        )
        return result
      end

      return result if segments.size < 2

      if metric.max_agg? || metric.latest_agg?
        return result unless card.billing_scope_cycle?

        result.cycle_usage_tracker = Fees::ChargeService::Trackers::CycleClosingUnits.new(maximum: metric.max_agg?)
      elsif metric.count_agg? || metric.sum_agg?
        return result if metric.recurring? || rate_card.proration?

        result.cycle_usage_tracker = Fees::ChargeService::Trackers::CycleCarryoverUnits.for(segments:, coverage_started_at: obligation.coverage_started_at)
      end
      result
    end

    private

    attr_reader :segments, :obligation
  end
end
