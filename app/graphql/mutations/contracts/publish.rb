# frozen_string_literal: true

module Mutations
  module Contracts
    class Publish < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "contracts:update"

      graphql_name "PublishContract"
      description "Publishes a draft contract so billing can start"

      input_object_class Types::Contracts::PublishInput
      type Types::Contracts::Object

      def resolve(id:)
        contract = current_organization.contracts.find_by(id:)

        result = ::Contracts::PublishService.call(contract:)

        result.success? ? result.contract : result_error(result)
      end
    end
  end
end
