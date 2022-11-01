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

      argument :items, [Types::CreditNoteItems::Input], required: true

      type Types::CreditNotes::Object

      def resolve(**args)
        validate_organization!
        args[:items].map!(&:to_h)

        result = ::CreditNotes::CreateService
          .new(
            invoice: current_organization.invoices.find_by(id: args[:invoice_id]),
            items_attr: args[:items],
            reason: args[:reason],
            description: args[:description],
          )
          .call

        result.success? ? result.credit_note : result_error(result)
      end
    end
  end
end
