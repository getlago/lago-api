# frozen_string_literal: true

module Mutations
  module FixedCharges
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "fixed_charges:delete"

      graphql_name "DestroyFixedCharge"
      description "Deletes a Fixed Charge"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        fixed_charge = current_organization.fixed_charges.parents.find_by(id:)

        result = ::FixedCharges::DestroyService.call(fixed_charge:)

        result.success? ? result.fixed_charge : result_error(result)
      end
    end
  end
end
