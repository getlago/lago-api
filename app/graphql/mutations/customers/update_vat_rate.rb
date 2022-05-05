# frozen_string_literal: true

module Mutations
  module Customers
    class UpdateVatRate < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateCustomerVatRate'
      description 'Assign the vat rate to Customers'

      argument :id, ID, required: true
      argument :vat_rate, Float, required: false

      type Types::Customers::SingleObject

      def resolve(id:, vat_rate:)
        result = CustomersService.new(context[:current_user]).update(
          id: id,
          vat_rate: vat_rate,
        )

        result.success? ? result.customer : result_error(result)
      end
    end
  end
end
