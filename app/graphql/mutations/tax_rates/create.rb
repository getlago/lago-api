# frozen_string_literal: true

module Mutations
  module TaxRates
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateTaxRate'
      description 'Creates a tax rate'

      input_object_class Types::TaxRates::CreateInput
      type Types::TaxRates::Object

      def resolve(**args)
        validate_organization!

        result = ::TaxRates::CreateService.call(organization: current_organization, params: args)
        result.success? ? result.tax_rate : result_error(result)
      end
    end
  end
end
