# frozen_string_literal: true

module Mutations
  module Contracts
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "UpdateContract"
      description "Updates a contract; once active, only its administrative settings"

      input_object_class Types::Contracts::UpdateInput
      type Types::Contracts::Object

      def resolve(id: nil, external_id: nil, **args)
        contract = if id
          current_organization.contracts.find_by(id:)
        else
          current_organization.contracts.live_by_external_id(external_id)
        end

        result = ::Contracts::UpdateService.call(contract:, params: args)

        result.success? ? result.contract : result_error(result)
      end
    end
  end
end
