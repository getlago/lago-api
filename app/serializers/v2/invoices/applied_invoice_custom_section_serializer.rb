# frozen_string_literal: true

module V2
  module Invoices
    class AppliedInvoiceCustomSectionSerializer < ModelSerializer
      timestamps :created_at, :updated_at

      def serialize
        {
          lago_id: model.id,
          lago_invoice_id: model.invoice_id,
          code: model.code,
          details: model.details,
          display_name: model.display_name
        }
      end
    end
  end
end
