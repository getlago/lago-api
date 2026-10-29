# frozen_string_literal: true

module V2
  class ProductFilterSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        product_code: model.product.code,
        product_category_code: model.product.product_category&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        values: values,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end

    private

    def values
      source_values = if model.discarded?
        []
      else
        model.values
      end

      source_values.map do |value|
        {
          key: value.key,
          value: value.value
        }
      end
    end
  end
end
