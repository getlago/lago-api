# frozen_string_literal: true

module Types
  module Fees
    class PresentationBreakdownBuilder
      def self.call(fees)
        units_by_presentation = Hash.new { |hash, key| hash[key] = BigDecimal(0) }

        Array(fees).each do |fee|
          fee.presentation_breakdowns.each do |breakdown|
            units_by_presentation[breakdown.presentation_by] += BigDecimal((breakdown.units || 0).to_s)
          end
        end

        units_by_presentation.map do |presentation_by, units|
          {
            presentation_by:,
            units: units.to_s
          }
        end
      end
    end
  end
end
