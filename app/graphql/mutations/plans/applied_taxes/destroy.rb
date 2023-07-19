# frozen_string_literal: true

module Mutations
  module Plans
    module AppliedTaxes
      class Destroy < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        graphql_name 'DestroyPlanAppliedTax'
        description 'Unassign a tax from a plan'

        argument :id, ID, required: true

        type Types::Plans::AppliedTaxes::Object

        def resolve(id:)
          validate_organization!

          applied_tax = ::Plan::AppliedTax.joins(tax: :organization)
            .where(organization: { id: current_organization.id })
            .find_by(id:)

          result = ::Plans::AppliedTaxes::DestroyService.call(applied_tax:)
          result.success? ? result.applied_tax : result_error(result)
        end
      end
    end
  end
end
