# frozen_string_literal: true

module CopyToProduction
  module Items
    class BillableMetricItem < BaseItem
      ATTRIBUTES = %i[
        name code description recurring aggregation_type field_name rounding_function rounding_precision
        weighted_interval expression
      ].freeze

      # `properties` is not copied: no code reads it, and the create service does not set it.
      def copy!(source, _resolved)
        BillableMetrics::CreateService.call!(
          **source.slice(*ATTRIBUTES).symbolize_keys,
          organization_id: production.id,
          filters: source.filters.map { |filter| {key: filter.key, values: filter.values} }
        ).billable_metric
      end
    end
  end
end
