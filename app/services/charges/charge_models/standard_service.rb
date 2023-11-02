# frozen_string_literal: true

module Charges
  module ChargeModels
    class StandardService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        (units * BigDecimal(properties['amount']))
      end

      def unit_amount
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        compute_amount / total_units
      end
    end
  end
end
