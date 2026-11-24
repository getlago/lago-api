# frozen_string_literal: true

module Mutations
  module Integrations
    module AgentStorefront
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "CreateAgentStorefrontIntegration"
        description "Create Agent Storefront integration"

        input_object_class Types::Integrations::AgentStorefront::CreateInput

        type Types::Integrations::AgentStorefront

        def resolve(**args)
          result = ::Integrations::AgentStorefront::CreateService.call(
            params: args.merge(organization_id: current_organization.id)
          )

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
