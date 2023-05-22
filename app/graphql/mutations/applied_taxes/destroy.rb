# frozen_string_literal: true

module Mutations
  module AppliedTaxes
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DestroyAppliedTax'
      description 'Unassign a tax from a customer'

      argument :id, ID, required: true

      type Types::AppliedTaxes::Object

      def resolve(id:)
        validate_organization!

        applied_tax = AppliedTax.joins(tax: :organization)
          .where(organizations: { id: current_organization.id })
          .find_by(id:)

        result = ::AppliedTaxes::DestroyService.call(applied_tax:)

        result.success? ? result.applied_tax : result_error(result)
      end
    end
  end
end
