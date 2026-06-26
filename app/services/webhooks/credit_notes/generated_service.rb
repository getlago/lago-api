# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Webhooks
  module CreditNotes
    class GeneratedService < Webhooks::BaseService
      private

      def object_serializer
        ::V1::CreditNoteSerializer.new(
          object,
          root_name: "credit_note",
          includes: %i[customer]
        )
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
