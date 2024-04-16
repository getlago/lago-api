# frozen_string_literal: true

module Charges
  module ChargeModels
    class CustomService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        # TODO(custom_agg): Implement custom aggregation logic
        0
      end

      def unit_amount
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        result.amount / total_units
      end
    end
  end
end
