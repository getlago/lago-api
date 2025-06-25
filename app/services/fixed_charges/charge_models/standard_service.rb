# frozen_string_literal: true

# NOTE: This service is a copy of the StandardService in the Charges namespace.
# Instead of duplicating the code, we could extract the charge models to its own scope
# and use it from both namespaces.
module FixedCharges
  module ChargeModels
    class StandardService < FixedCharges::ChargeModels::BaseService
      protected

      def compute_amount
        # Simple calculation: aggregated units * full amount
        # For prorated charges, the aggregated units are already prorated
        # For non-prorated charges, the aggregated units are the full units
        units * BigDecimal(properties["amount"])
      end

      def unit_amount
        total_units = aggregation_result.full_units_number || units
        return 0 if total_units.zero?

        compute_amount / total_units
      end
    end
  end
end
