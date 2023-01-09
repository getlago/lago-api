# frozen_string_literal: true

module Mutations
  module CreditNotes
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCreditNote'
      description 'Creates a new Credit Note'

      argument :reason, Types::CreditNotes::ReasonTypeEnum, required: true
      argument :invoice_id, ID, required: true
      argument :description, String, required: false

      argument :credit_amount_cents, GraphQL::Types::BigInt, required: false
      argument :refund_amount_cents, GraphQL::Types::BigInt, required: false

      argument :items, [Types::CreditNoteItems::Input], required: true

      type Types::CreditNotes::Object

      def resolve(**args)
        validate_organization!
        args[:items].map!(&:to_h)

        result = ::CreditNotes::CreateService
          .new(
            invoice: current_organization.invoices.finalized.find_by(id: args[:invoice_id]),
            **args,
          )
          .call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
