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
        :tax_breakdown,
        :group_key,
        :group_tax_amount_cents
      ) do
        def initialize(group_key: nil, group_tax_amount_cents: nil, **) = super
      end

      TaxResult::TaxBreakdownItem = Data.define(
        :name,
        :rate,
        :tax_amount,
        :type,
        :allocated_amount_cents
      ) do
        def initialize(allocated_amount_cents: nil, **) = super
      end
    end
  end
end
