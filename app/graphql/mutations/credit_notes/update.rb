# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "credit_notes:update"

      graphql_name "UpdateCreditNote"
      description "Updates an existing Credit Note"

      input_object_class Types::CreditNotes::UpdateCreditNoteInput

      type Types::CreditNotes::Object

      def resolve(**args)
        result = ::CreditNotes::UpdateService.new(
          credit_note: context[:current_user].credit_notes.find_by(id: args[:id]),
          refund_status: args[:refund_status],
          metadata: args[:metadata]
        ).call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
