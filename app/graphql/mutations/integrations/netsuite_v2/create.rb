# frozen_string_literal: true

module Mutations
  module Integrations
    module NetsuiteV2
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "CreateNetsuiteV2Integration"
        description "Create Netsuite V2 integration"

        input_object_class Types::Integrations::NetsuiteV2::CreateInput

        type Types::Integrations::NetsuiteV2

        def resolve(**args)
          result = ::Integrations::NetsuiteV2::CreateService
            .call(params: args.merge(organization_id: current_organization.id))

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
