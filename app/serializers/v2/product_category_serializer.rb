# frozen_string_literal: true

module V2
  class ProductCategorySerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        **counts,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **deleted_at_payload
      }
    end

    private

    def counts = include?(:counts) ? {products_count: model.products.size} : {}
  end
end
