# frozen_string_literal: true

module Mutations
  module IntegrationCollectionMappings
    module Netsuite
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = 'organization:integrations:update'

        graphql_name 'UpdateNetsuiteIntegrationCollectionMapping'
        description 'Update Netsuite integration mapping'

        input_object_class Types::IntegrationCollectionMappings::Netsuite::UpdateInput

        type Types::IntegrationCollectionMappings::Netsuite::Object

        def resolve(**args)
          integration_collection_mapping = ::IntegrationCollectionMappings::NetsuiteCollectionMapping
            .joins(:integration)
            .where(id: args[:id], integration: { organization: current_organization }).first

          result = ::IntegrationCollectionMappings::Netsuite::UpdateService.call(
            integration_collection_mapping:,
            params: args,
          )

          result.success? ? result.integration_collection_mapping : result_error(result)
        end
      end
    end
  end
end
