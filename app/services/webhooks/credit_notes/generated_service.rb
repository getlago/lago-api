# frozen_string_literal: true

module Webhooks
  module CreditNotes
    class GeneratedService < Webhooks::BaseService
      private

      def object_serializer
        if object.invoice.product_catalog?
          ::V2::CreditNoteSerializer.new(object, root_name: "credit_note")
        else
          ::V1::CreditNoteSerializer.new(
            object,
            root_name: "credit_note",
            includes: %i[customer]
          )
        end
      end

      def webhook_type
        "credit_note.generated"
      end

      def object_type
        "credit_note"
      end
    end
  end
end
