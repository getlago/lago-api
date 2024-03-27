# frozen_string_literal: true

module Mutations
  module Invoices
    class Finalize < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "FinalizeInvoice"
      description "Finalize a draft invoice"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        validate_organization!
        result = ::Invoices::FinalizeService.call(
          invoice: current_organization.invoices.draft.find_by(id: args[:id])
        )
        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
