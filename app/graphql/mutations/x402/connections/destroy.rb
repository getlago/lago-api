# frozen_string_literal: true

module Mutations
  module X402
    module Connections
      class Destroy < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:delete"

        graphql_name "DestroyX402Connection"
        description "Deletes an x402 connection"

        argument :id, ID, required: true

        field :id, ID, null: true

        def resolve(id:)
          raise forbidden_error(code: "feature_unavailable") unless current_organization.x402_payments_enabled?

          connection = current_organization.x402_connections.find_by(id:)
          result = ::X402::Connections::DestroyService.call(connection:)

          result.success? ? result.connection : result_error(result)
        end
      end
    end
  end
end
