# frozen_string_literal: true

module Mutations
  module TaxRates
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateTaxRate'
      description 'Update an existing tax rate'

      input_object_class Types::TaxRates::UpdateInput
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
