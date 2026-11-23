# frozen_string_literal: true

module Mutations
  module Contracts
    class Terminate < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:terminate"

      graphql_name "TerminateContract"
      description "Terminates a live contract"

      input_object_class Types::Contracts::TerminateInput
      type Types::Contracts::Object

      def resolve(id:)
        contract = current_organization.contracts.find_by(id:)

        result = ::Contracts::TerminateService.call(contract:)

        result.success? ? result.contract : result_error(result)
      end
    end
  end
end
