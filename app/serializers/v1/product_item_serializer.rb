# frozen_string_literal: true

module V1
  class ProductItemSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_product_id: model.product_id,
        lago_billable_metric_id: model.billable_metric_id,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        item_type: model.item_type,
        attached_to_plan_or_subscription: model.attached_to_plan_or_subscription?,
        created_at: model.created_at.iso8601
      }
    end
  end
end
