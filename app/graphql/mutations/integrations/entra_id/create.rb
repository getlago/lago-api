# frozen_string_literal: true

module Mutations
  module Integrations
    module EntraId
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "CreateEntraIdIntegration"
        description "Create Entra ID integration"

        input_object_class Types::Integrations::EntraId::CreateInput

        type Types::Integrations::EntraId

        def resolve(**args)
          result = ::Integrations::EntraId::CreateService
            .new(context[:current_user])
            .call(**args.merge(organization_id: current_organization.id))

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
