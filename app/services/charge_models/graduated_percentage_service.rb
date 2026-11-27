# frozen_string_literal: true

module ChargeModels
  class GraduatedPercentageService < ChargeModels::BaseService
    include AdjacentRanges

    protected

    def ranges
      properties["graduated_percentage_ranges"]&.map(&:with_indifferent_access)
    end

    def amount_details
      @amount_details ||= {
        graduated_percentage_ranges: priced_ranges(units) do |range, range_units|
          detail = ChargeModels::AmountDetails::RangeGraduatedPercentageService.call(range:, units: range_units)
          # On the first pay-in-advance event: delta = cost(1 unit) - cost(0 units, exclude_event: true).
          # Here we exclude the flat fee from cost(0 units, exclude_event: true).
          (units.zero? && properties[:exclude_event]) ? detail.merge(flat_unit_amount: 0, total_with_flat_amount: 0) : detail
        end
      }
    end

    # Subscription percentage tiers retain their one-unit step even when the bounds touch.
    def half_open_ranges?(tiers)
      pricing_structure.product_catalog && super
    end

    def compute_amount
      amount_details.fetch(:graduated_percentage_ranges).sum { |e| e[:total_with_flat_amount] }
    end

    def compute_projected_amount
      current_amount = compute_amount
      return BigDecimal(0) if current_amount.zero? || period_ratio.nil? || period_ratio.zero?

      current_amount / BigDecimal(period_ratio.to_s)
    end

    def unit_amount
      total_units = aggregation_result.full_units_number || units
      return 0 if total_units.zero?

      compute_amount / total_units
    end
  end
end
