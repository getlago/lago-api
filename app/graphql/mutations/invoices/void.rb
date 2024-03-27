# frozen_string_literal: true

module Mutations
  module Invoices
    class Void < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "VoidInvoice"
      description "Void an invoice"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        validate_organization!
        result = ::Invoices::VoidService.call(
          invoice: current_organization.invoices.not_generating.find_by(id: args[:id])
        )
        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
