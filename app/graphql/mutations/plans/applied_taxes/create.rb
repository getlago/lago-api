# frozen_string_literal: true

module Mutations
  module Plans
    module AppliedTaxes
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        graphql_name 'CreatePlanAppliedTax'
        description 'Assign a tax to a plan'

        argument :plan_id, ID, required: true
        argument :tax_id, ID, required: true

        type Types::Plans::AppliedTaxes::Object

        def resolve(**args)
          validate_organization!

          plan = current_organization.plans.find_by(id: args[:plan_id])
          tax = current_organization.taxes.find_by(id: args[:tax_id])

          result = ::Plans::AppliedTaxes::CreateService.call(plan:, tax:)
          result.success? ? result.applied_tax : result_error(result)
        end
      end
    end
  end
end
