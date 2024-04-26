# frozen_string_literal: true

module Mutations
  module IntegrationMappings
    module Netsuite
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = 'organization:integrations:update'

        graphql_name 'UpdateNetsuiteIntegrationMapping'
        description 'Update Netsuite integration mapping'

        input_object_class Types::IntegrationMappings::Netsuite::UpdateInput

        type Types::IntegrationMappings::Netsuite::Object

        def resolve(**args)
          integration_mapping = ::IntegrationMappings::NetsuiteMapping
            .joins(:integration)
            .where(id: args[:id], integration: { organization: current_organization }).first

          result = ::IntegrationMappings::Netsuite::UpdateService.call(integration_mapping:, params: args)

          result.success? ? result.integration_mapping : result_error(result)
        end
      end
    end
  end
end
