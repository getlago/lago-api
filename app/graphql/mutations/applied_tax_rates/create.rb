# frozen_string_literal: true

module Mutations
  module AppliedTaxRates
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateAppliedTaxRate'
      description 'Assign a tax rate to a customer'

      argument :customer_id, ID, required: true
      argument :tax_rate_id, ID, required: true

      type Types::AppliedTaxRates::Object

      def resolve(**args)
        validate_organization!

        customer = current_organization.customers.find_by(id: args[:customer_id])
        tax_rate = current_organization.tax_rates.find_by(id: args[:tax_rate_id])

        result = ::AppliedTaxRates::CreateService.call(customer:, tax_rate:)
        result.success? ? result.applied_tax_rate : result_error(result)
      end
    end
  end
end
