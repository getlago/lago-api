# frozen_string_literal: true

module V2
  class ProductFilterSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    def serialize
      {
        lago_id: model.id,
        product_code: model.product.code,
        product_category_code: model.product.product_category&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        values: values
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
