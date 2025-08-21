# frozen_string_literal: true

module Mutations
  module CustomerPortal
    class DownloadInvoiceXml < BaseMutation
      include AuthenticableCustomerPortalUser

      graphql_name "DownloadCustomerPortalInvoiceXml"
      description "Download customer portal invoice XML"

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(id:)
        invoice = context[:customer_portal_user].invoices.visible.find_by(id:)
        result = ::Invoices::GenerateXmlService.call(invoice:)
        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
