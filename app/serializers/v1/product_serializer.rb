# frozen_string_literal: true

module V1
  class ProductSerializer < ModelSerializer
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
        filters_count: model.filters.size,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
