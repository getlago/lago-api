# frozen_string_literal: true

module V2
  module Invoices
    class AppliedInvoiceCustomSectionSerializer < ModelSerializer
      def serialize
        {
          lago_id: model.id,
          lago_invoice_id: model.invoice_id,
          code: model.code,
          details: model.details,
          display_name: model.display_name,
          created_at: format_time(model.created_at),
          updated_at: format_time(model.updated_at)
        }
      end
    end
  end
end
