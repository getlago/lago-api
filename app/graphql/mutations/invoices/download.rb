# frozen_string_literal: true

module Mutations
  module Invoices
    class Download < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DownloadInvoice'
      description 'Download an Invoice PDF'

      argument :id, ID, required: true

      type Types::Invoices::Object

      def resolve(**args)
        validate_organization!

        result = ::Invoices::GenerateService.new.generate(invoice_id: args[:id])

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
