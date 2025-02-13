# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Void < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "credit_notes:void"

      graphql_name "VoidCreditNote"
      description "Voids a Credit Note"

      argument :id, ID, required: true

      type Types::CreditNotes::Object

      def resolve(id:)
        result = ::CreditNotes::VoidService.new(
          credit_note: context[:current_user].credit_notes.find_by(id:)
        ).call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
