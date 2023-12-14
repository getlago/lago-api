# frozen_string_literal: true

module Mutations
  module Invoices
    class Update < BaseMutation
      include AuthenticableApiUser
      description 'Update an existing invoice'
      graphql_name 'UpdateInvoice'

      input_object_class Types::Invoices::UpdateInvoiceInput

      type Types::Invoices::Object

      def resolve(**args)
        invoice = context[:current_organization].invoices.not_generating.find_by(id: args[:id])
        result = ::Invoices::UpdateService.new(invoice:, params: args, webhook_notification: true).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
