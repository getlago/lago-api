# frozen_string_literal: true

module Mutations
  module Invoices
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateInvoice'
      description 'Update an existing invoice'

      argument :id, ID, required: true
      argument :payment_status, Types::Invoices::PaymentStatusTypeEnum, required: false

      type Types::Invoices::Object

      def resolve(**args)
        invoice = context[:current_organization].invoices.find_by(id: args[:id])
        result = ::Invoices::UpdateService.new(invoice:, params: args).call

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
