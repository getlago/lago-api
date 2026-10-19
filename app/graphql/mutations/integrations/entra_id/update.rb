# frozen_string_literal: true

module Mutations
  module Integrations
    module EntraId
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        # NOTE: The integration decides who can log in to the organization, so it is managed
        #       with the authentication methods rather than with the other integrations.
        REQUIRED_PERMISSION = "authentication_methods:update"

        graphql_name "UpdateEntraIdIntegration"
        description "Update Entra ID integration"

        input_object_class Types::Integrations::EntraId::UpdateInput

        type Types::Integrations::EntraId

        def resolve(**args)
          integration = current_organization.integrations.find_by(id: args[:id])
          result = ::Integrations::EntraId::UpdateService.call(integration:, params: args)

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
