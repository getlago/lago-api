# frozen_string_literal: true

module CopyToProduction
  module Items
    class BillableMetricItem < BaseItem
      ATTRIBUTES = %i[
        name code description recurring aggregation_type field_name rounding_function rounding_precision
        weighted_interval expression
      ].freeze

      def find_source(id)
        sandbox.billable_metrics.includes(:filters).find_by(id:)
      end

      def find_existing(source)
        production.billable_metrics.find_by(code: source.code)
      end

      # The custom aggregator is code set by hand on a deprecated aggregation, which the create service cannot set.
      def refusal(source)
        "copy_to_production_item_unsupported" if source.custom_agg?
      end

      # `properties` is not copied: no code reads it, and the create service does not set it.
      def copy!(source, _resolved)
        BillableMetrics::CreateService.call!(
          **source.slice(*ATTRIBUTES).symbolize_keys,
          organization_id: production.id,
          filters: source.filters.map { |filter| {key: filter.key, values: filter.values} }
        ).billable_metric
      end

      def unique_indexes
        {"index_billable_metrics_on_organization_id_and_code" => :code}
      end
    end
  end
end
