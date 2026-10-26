# frozen_string_literal: true

module V2
  # V1's fields without the organization, plus the timestamps.
  class InvoiceCustomSectionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        name: model.name,
        description: model.description,
        details: model.details,
        display_name: model.display_name,
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end
  end
end
