# frozen_string_literal: true

module V1
  class AppliedInvoiceCustomSectionSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        invoice_custom_section_id: model.invoice_custom_section_id,
        created_at: model.created_at.iso8601
      }
    end
  end
end
