# frozen_string_literal: true

module Mutations
  module Invoices
    class Delete < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:delete"

      graphql_name "DeleteInvoice"
      description "Delete a draft invoice"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        result = ::Invoices::DeleteService.call(
          invoice: current_organization.invoices.visible.find_by(id: args[:id])
        )

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
