# frozen_string_literal: true

module V1
  class ProductItemFilterSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        values: values,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end

    private

    # options[:values] lets the destroy endpoint echo values discarded by the service
    def values
      (options[:values] || model.values).map do |value|
        {
          key: value.key,
          value: value.value
        }
      end
    end
  end
end
