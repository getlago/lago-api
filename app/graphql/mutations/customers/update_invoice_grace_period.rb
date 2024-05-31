# frozen_string_literal: true

# TODO: Remove this mutation
# The Mutations::Customers::Update allows you to modify the customer grace period
module Mutations
  module Customers
    class UpdateInvoiceGracePeriod < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = %w[customers:update customer_settings:update:grace_period]

      graphql_name 'UpdateCustomerInvoiceGracePeriod'
      description 'Assign the invoice grace period to Customers'

      argument :id, ID, required: true
      argument :invoice_grace_period, Integer, required: false

      type Types::Customers::Object

      def resolve(id:, invoice_grace_period:)
        result = ::Customers::UpdateService.new(context[:current_user]).update(id:, invoice_grace_period:)

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
