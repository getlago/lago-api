# frozen_string_literal: true

module ChargeModels
  class GraduatedPercentageService < ChargeModels::BaseService
    protected

    def ranges
      properties["graduated_percentage_ranges"]&.map(&:with_indifferent_access)
    end

    def amount_details
      {
        graduated_percentage_ranges: ranges.each_with_object([]) do |range, amounts|
          detail = ChargeModels::AmountDetails::RangeGraduatedPercentageService.call(range:, total_units: units)
          # First pay-in-advance event: delta = cost(1 unit) - cost(0 units, exclude_event: true).
          # Avoid including the flat fee here so it does not get subtracted from the delta.
          detail = detail.merge(flat_unit_amount: 0, total_with_flat_amount: 0) if units.zero? && properties[:exclude_event]
          amounts << detail
          break amounts if range[:to_value].nil? || range[:to_value] >= units
        end
      }
    end

    def compute_amount
      amount_details.fetch(:graduated_percentage_ranges).sum { |e| e[:total_with_flat_amount] }
    end

    def compute_projected_amount
      current_amount = compute_amount
      return BigDecimal("0") if current_amount.zero? || period_ratio.nil? || period_ratio.zero?

      current_amount / BigDecimal(period_ratio.to_s)
    end

    def unit_amount
      total_units = aggregation_result.full_units_number || units
      return 0 if total_units.zero?

      compute_amount / total_units
    end
  end
end
