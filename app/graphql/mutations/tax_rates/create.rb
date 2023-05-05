# frozen_string_literal: true

module Mutations
  module TaxRates
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateTaxRate'
      description 'Creates a tax rate'

      argument :code, String, required: true
      argument :description, String, required: false
      argument :name, String, required: true
      argument :value, Float, required: true

      type Types::TaxRates::Object

      def resolve(**args)
        validate_organization!

        result = ::TaxRates::CreateService.call(organization: current_organization, params: args)
        result.success? ? result.tax_rate : result_error(result)
      end
    end
  end
end
