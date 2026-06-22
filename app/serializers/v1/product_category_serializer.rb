# frozen_string_literal: true

module V1
  class ProductCategorySerializer < ModelSerializer
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
        products_count: model.products.count,
        created_at: model.created_at.iso8601
>>>>>>> 4c82f2f7b (feat(product_categories): expose products_count on the product_category API)
      }
    end
  end
end
