# frozen_string_literal: true

module V2
  module ContractAlertScope
    private

    def scope_of(alert)
      return [] unless alert.product

      target = if alert.product_filter
        {product_filter_codes: [alert.product_filter.code]}
      else
        {with_product_filters: alert.with_product_filters}
      end

      [{type: "contract", product_code: alert.product.code, **target}]
    end
  end
end
