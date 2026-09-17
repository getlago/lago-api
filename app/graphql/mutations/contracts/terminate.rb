# frozen_string_literal: true

module Mutations
  module Contracts
    class Terminate < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "TerminateContract"
      description "Terminates a live contract"

      input_object_class Types::Contracts::TerminateInput
      type Types::Contracts::Object

      def resolve(external_id:)
        contract = current_organization.contracts.terminatable_by_external_id(external_id)

        result = ::Contracts::TerminateService.call(contract:)

        result.success? ? result.contract : result_error(result)
      end
    end
  end
end
