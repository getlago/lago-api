# frozen_string_literal: true

module Mutations
  module Invoices
    class RetryPayment < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:update"

      graphql_name "RetryInvoicePayment"
      description "Retry invoice payment"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        invoice = current_organization.invoices.visible.find_by(id: args[:id])
        result = ::Invoices::Payments::RetryService.new(invoice:).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
