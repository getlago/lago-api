# frozen_string_literal: true

module Mutations
  module Invoices
    class Regenerate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:update"

      graphql_name "RegenerateInvoice"
      description "Regenerate an invoice from a voided invoice"

      argument :voided_invoice_id, ID, required: true
      argument :fees, [Types::Invoices::RegenerateInvoiceFeeInput], required: true

      type Types::Invoices::Object

      def resolve(voided_invoice_id:, fees:)
        invoice = current_organization.invoices.visible.find_by(id: voided_invoice_id)

        result = ::Invoices::RegenerateService.new(invoice:, fees:).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end