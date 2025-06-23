# frozen_string_literal: true

# app/graphql/mutations/invoices/regenerate_from_voided.rb
module Mutations
  module Invoices
    class RegenerateFromVoided < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:update"

      graphql_name "RegenerateInvoice"
      description "Regenerate an invoice from a voided invoice"

      argument :fees, [Types::Invoices::FeeInput], required: true
      argument :voided_invoice_id, ID, required: true

      type Types::Invoices::Object

      def resolve(voided_invoice_id:, fees:)
        invoice = current_organization.invoices.visible.find_by(id: voided_invoice_id)

        result = ::Invoices::RegenerateService.new(invoice:, fees:).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
