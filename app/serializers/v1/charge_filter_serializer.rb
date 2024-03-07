# frozen_string_literal: true

module V1
  class ChargeFilterSerializer < ModelSerializer
    def serialize
      {
        invoice_display_name: model.invoice_display_name,
        properties: model.properties,
        values:,
      }
    end

    private

    def values
      model.values.each_with_object({}) do |filter_value, result|
        result[filter_value.billable_metric_filter.key] = filter_value.value
      end
    end
  end
end
