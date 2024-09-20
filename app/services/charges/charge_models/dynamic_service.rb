# frozen_string_literal: true

module Charges
  module ChargeModels
    class DynamicService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        aggregation_result.precise_total_amount_cents
      end

      def unit_amount
        # eventhough `full_units_number` is not set by the SumService, we still keep this code as is, to be future proof
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        compute_amount / total_units
      end
    end
  end
end
