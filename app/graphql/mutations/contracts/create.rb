# frozen_string_literal: true

module Mutations
  module Contracts
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:create"

      graphql_name "CreateContract"
      description "Creates a new contract"

      input_object_class Types::Contracts::CreateInput
      type Types::Contracts::Object

      def resolve(**args)
        result = ::Contracts::CreateService.call(
          organization: current_organization,
          params: args
        )

        result.success? ? result.contract : result_error(result)
      end
    end
  end
end
