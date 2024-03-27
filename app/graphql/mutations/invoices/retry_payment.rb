# frozen_string_literal: true

module Mutations
  module Invoices
    class RetryPayment < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "RetryInvoicePayment"
      description "Retry invoice payment"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        validate_organization!

        invoice = current_organization.invoices.not_generating.find_by(id: args[:id])
        result = ::Invoices::Payments::RetryService.new(invoice:).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
