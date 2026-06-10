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
        created_at: model.created_at.iso8601
      }
    end
  end
end
