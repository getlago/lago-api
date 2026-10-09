# frozen_string_literal: true

module V2
  class ProductSerializer < ModelSerializer
    EXPANDABLE_RELATIONS = {product_category: :product_category, billable_metric: :billable_metric}.freeze

    def self.expandable_relations
      EXPANDABLE_RELATIONS
    end

    def serialize
      {
        lago_id: model.id,
        product_category_code: model.product_category&.code,
        billable_metric_code: model.billable_metric&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        product_type: model.product_type,
        **counts,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **deleted_at_payload,
        **expanded_payload
      }
    end

    private

    def counts = include?(:counts) ? {filters_count: model.filters.size} : {}

    def expand(name)
      case name
      when :product_category
        model.product_category&.then { ::V2::ProductCategorySerializer.new(it, includes: nested_includes).serialize }
      when :billable_metric
        # The association reads the metric with_discarded, so that a discarded one carries its deleted_at.
        model.billable_metric&.then { ::V2::BillableMetricSerializer.new(it, includes: nested_includes).serialize }
      else
        super
      end
    end
  end
end
