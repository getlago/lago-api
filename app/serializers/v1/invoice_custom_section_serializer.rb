# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class InvoiceCustomSectionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        code: model.code,
        name: model.name,
        description: model.description,
        details: model.details,
        display_name: model.display_name,
        organization_id: model.organization_id
      }
    end
  end
end
