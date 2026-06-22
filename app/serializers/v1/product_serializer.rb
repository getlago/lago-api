# frozen_string_literal: true

module V1
  class ProductSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
<<<<<<< HEAD
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
=======
        product_items_count: model.product_items.count,
        created_at: model.created_at.iso8601
>>>>>>> 4c82f2f7b (feat(products): expose product_items_count on the product API)
      }
    end
  end
end
