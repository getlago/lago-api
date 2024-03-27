# frozen_string_literal: true

module Mutations
  module Invoices
    class Download < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "DownloadInvoice"
      description "Download an Invoice PDF"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(id:)
        validate_organization!

        invoice = Invoice.not_generating.find_by(id:, organization_id: current_organization.id)
        result = ::Invoices::GeneratePdfService.call(invoice:)
        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
