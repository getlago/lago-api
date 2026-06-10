# frozen_string_literal: true

module V1
  class ProductItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        product_code: model.product&.code,
        billable_metric_code: model.billable_metric&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        item_type: model.item_type,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
