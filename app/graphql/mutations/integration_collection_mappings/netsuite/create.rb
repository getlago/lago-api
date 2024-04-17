# frozen_string_literal: true

module Mutations
  module IntegrationCollectionMappings
    module Netsuite
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        graphql_name 'CreateNetsuiteIntegrationCollectionMapping'
        description 'Create Netsuite integration collection mapping'

        input_object_class Types::IntegrationCollectionMappings::Netsuite::CreateInput

        type Types::IntegrationCollectionMappings::Netsuite::Object

        def resolve(**args)
          result = ::IntegrationCollectionMappings::Netsuite::CreateService
            .new(context[:current_user])
            .call(**args.merge(organization_id: current_organization.id))

          result.success? ? result.integration_collection_mapping : result_error(result)
        end
      end
    end
  end
end
