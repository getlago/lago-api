# frozen_string_literal: true

module Mutations
  module AppliedTaxes
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAppliedTax'
      description 'Assign a tax to a customer'

      argument :customer_id, ID, required: true
      argument :tax_id, ID, required: true

      type Types::AppliedTaxes::Object

      def resolve(**args)
        validate_organization!

        customer = current_organization.customers.find_by(id: args[:customer_id])
        tax = current_organization.taxes.find_by(id: args[:tax_id])

        result = ::AppliedTaxes::CreateService.call(customer:, tax:)
        result.success? ? result.applied_tax : result_error(result)
      end
    end
  end
end
