# frozen_string_literal: true

module Fees
  # Only sound for aggregations whose windows add up and charge models that price linearly, which
  # Fees::FullUsageChargeService restricts callers to.
  class MergePeriodFeesService < BaseService
    Result = BaseResult[:fees]

    SUMMED_ATTRIBUTES = %w[
      amount_cents
      precise_amount_cents
      units
      total_aggregated_units
      events_count
    ].freeze

    def initialize(earlier_fees:, later_fees:)
      @earlier_fees = earlier_fees
      @later_fees = later_fees
      super
    end

    def call
      result.fees = merged_filter_ids.map { merge(earlier_by_filter[it], later_by_filter[it]) }
      result
    end

    private

    attr_reader :earlier_fees, :later_fees

    def earlier_by_filter
      @earlier_by_filter ||= earlier_fees.index_by(&:charge_filter_id)
    end

    def later_by_filter
      @later_by_filter ||= later_fees.index_by(&:charge_filter_id)
    end

    def merged_filter_ids
      later_by_filter.keys | earlier_by_filter.keys
    end

    def merge(earlier, later)
      return later if earlier.nil?
      return earlier if later.nil?

      fee = later
      SUMMED_ATTRIBUTES.each { fee[it] = (fee[it] || 0).to_d + (earlier[it] || 0).to_d }

      merge_pricing_unit_usage(earlier, fee)
      merge_presentation_breakdowns(earlier, fee)

      fee
    end

    def merge_pricing_unit_usage(earlier, fee)
      return if earlier.pricing_unit_usage.nil?

      if fee.pricing_unit_usage.nil?
        fee.pricing_unit_usage = earlier.pricing_unit_usage
      else
        fee.pricing_unit_usage.amount_cents += earlier.pricing_unit_usage.amount_cents
        fee.pricing_unit_usage.precise_amount_cents += earlier.pricing_unit_usage.precise_amount_cents
      end
    end

    def merge_presentation_breakdowns(earlier, fee)
      return if earlier.presentation_breakdowns.blank?

      existing = fee.presentation_breakdowns.index_by(&:presentation_by)

      earlier.presentation_breakdowns.each do |breakdown|
        match = existing[breakdown.presentation_by]

        if match
          match.units = match.units.to_d + breakdown.units.to_d
        else
          fee.presentation_breakdowns.build(
            organization_id: breakdown.organization_id,
            presentation_by: breakdown.presentation_by,
            units: breakdown.units
          )
        end
      end
    end
  end
end
