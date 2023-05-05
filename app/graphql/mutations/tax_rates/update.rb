# frozen_string_literal: true

module Mutations
  module TaxRates
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateTaxRate'
      description 'Update an existing tax rate'

      argument :code, String, required: true
      argument :description, String, required: false
      argument :id, ID, required: true
      argument :name, String, required: true
      argument :value, Float, required: true

      type Types::TaxRates::Object

      def resolve(**args)
        validate_organization!

        tax_rate = current_organization.tax_rates.find_by(id: args[:id])
        result = ::TaxRates::UpdateService.call(tax_rate:, params: args)

        result.success? ? result.tax_rate : result_error(result)
      end
    end
  end
end
