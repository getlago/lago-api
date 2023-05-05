# frozen_string_literal: true

module Mutations
  module TaxRates
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DestroyTaxRate'
      description 'Deletes a tax rate'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        validate_organization!

        tax_rate = current_organization.tax_rates.find_by(id:)
        result = ::TaxRates::DestroyService.call(tax_rate:)

        result.success? ? result.tax_rate : result_error(result)
      end
    end
  end
end
