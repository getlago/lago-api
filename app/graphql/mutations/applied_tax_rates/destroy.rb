# frozen_string_literal: true

module Mutations
  module AppliedTaxRates
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DestroyAppliedTaxRate'
      description 'Unassign a tax rate from a customer'

      argument :id, ID, required: true

      type Types::AppliedTaxRates::Object

      def resolve(id:)
        validate_organization!

        applied_tax_rate = AppliedTaxRate.joins(tax_rate: :organization)
          .where(organizations: { id: current_organization.id })
          .find_by(id:)

        result = ::AppliedTaxRates::DestroyService.call(applied_tax_rate:)

        result.success? ? result.applied_tax_rate : result_error(result)
      end
    end
  end
end
