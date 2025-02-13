# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "credit_notes:update"

      graphql_name "UpdateCreditNote"
      description "Updates an existing Credit Note"

      argument :id, ID, required: true
      argument :refund_status, Types::CreditNotes::RefundStatusTypeEnum, required: true

      type Types::CreditNotes::Object

      def resolve(**args)
        result = ::CreditNotes::UpdateService.new(
          credit_note: context[:current_user].credit_notes.find_by(id: args[:id]),
          refund_status: args[:refund_status]
        ).call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
