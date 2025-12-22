# frozen_string_literal: true

module Mutations
  module Integrations
    module NetsuiteV2
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateNetsuiteV2Integration"
        description "Update Netsuite V2 integration"

        input_object_class Types::Integrations::NetsuiteV2::UpdateInput

        type Types::Integrations::NetsuiteV2

        def resolve(**args)
          integration = current_organization.integrations.find_by(id: args[:id])
          result = ::Integrations::NetsuiteV2::UpdateService.call(integration:, params: args)

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
