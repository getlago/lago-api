# app/graphql/mutations/invoices/voided_regenerate.rb
module Mutations
  module Invoices
    class VoidedRegenerate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "invoices:void"

      graphql_name "VoidedRegenerationInvoice"
      description "Regenerate an invoice from a voided invoice"

      argument :voided_invoice_id, ID, required: true
      argument :fees, [Types::FeeType], required: true

      field :invoice, Types::InvoiceType, null: true
      field :errors, [String], null: false

      def resolve(voided_invoice_id:)
        result = ::Invoices::Voids::RegenerateFromVoidedInvoiceService.call(voided_invoice_id: voided_invoice_id)

        if result.success?
          { invoice: result.invoice, errors: [] }
        else
          { invoice: nil, errors: [result.error] }
        end
      end
    end
  end
end
