# frozen_string_literal: true

module V2
  # The fields of V1, without the organization, plus the timestamps.
  class InvoiceCustomSectionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        name: model.name,
        description: model.description,
        details: model.details,
        display_name: model.display_name,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **deleted_at_payload
      }
    end
  end
end
