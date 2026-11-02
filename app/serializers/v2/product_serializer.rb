# frozen_string_literal: true

module V2
  class ProductSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    expandable :product_category, serializer: ::V2::ProductCategorySerializer
    # Read with_discarded, so that a deleted metric expands with its deleted_at.
    expandable :billable_metric, serializer: ::V2::BillableMetricSerializer

    def serialize
      {
        lago_id: model.id,
        product_category_code: model.product_category&.code,
        billable_metric_code: model.billable_metric&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        product_type: model.product_type
      }
    end
  end
end
