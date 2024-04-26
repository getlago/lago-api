# frozen_string_literal: true

module Mutations
  module IntegrationMappings
    module Netsuite
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = 'organization:integrations:update'

        graphql_name 'CreateNetsuiteIntegrationMapping'
        description 'Create Netsuite integration mapping'

        input_object_class Types::IntegrationMappings::Netsuite::CreateInput

        type Types::IntegrationMappings::Netsuite::Object

        def resolve(**args)
          result = ::IntegrationMappings::Netsuite::CreateService
            .new(context[:current_user])
            .call(**args.merge(organization_id: current_organization.id))

          result.success? ? result.integration_mapping : result_error(result)
        end
      end
    end
  end
end
