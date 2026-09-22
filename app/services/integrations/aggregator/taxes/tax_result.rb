# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      TaxResult = Data.define(
        :item_key,
        :item_id,
        :item_code,
        :amount_cents,
        :tax_amount_cents,
        :tax_breakdown
      ) do
        # Reconcile the provider's line total with its jurisdiction breakdown.
        def allocated_amounts
          weights = tax_breakdown.map { |tax| tax.tax_amount || 0 }
          Allocation.call(tax_amount_cents || weights.sum, weights)
        end
      end

      TaxResult::TaxBreakdownItem = Data.define(
        :name,
        :rate,
        :tax_amount,
        :type
      )
    end
  end
end
