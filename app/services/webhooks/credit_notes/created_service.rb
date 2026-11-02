# frozen_string_literal: true

module Webhooks
  module CreditNotes
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        if object.invoice.product_catalog?
          ::V2::CreditNoteSerializer.new(object, root_name: "credit_note")
        else
          ::V1::CreditNoteSerializer.new(
            object,
            root_name: "credit_note",
            includes: %i[customer items applied_taxes]
          )
        end
      end

      def webhook_type
        "credit_note.created"
      end

      def object_type
        "credit_note"
      end
    end
  end
end
