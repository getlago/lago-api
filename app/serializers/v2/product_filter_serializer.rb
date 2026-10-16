# frozen_string_literal: true

module V2
  class ProductFilterSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        description: model.description,
        invoice_display_name: model.invoice_display_name,
        values: values,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        **deleted_at_payload
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
