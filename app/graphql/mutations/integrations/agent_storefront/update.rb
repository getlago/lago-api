# frozen_string_literal: true

module Mutations
  module Integrations
    module AgentStorefront
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateAgentStorefrontIntegration"
        description "Update Agent Storefront integration"

        input_object_class Types::Integrations::AgentStorefront::UpdateInput

        type Types::Integrations::AgentStorefront

        def resolve(**args)
          integration = current_organization.agent_storefront_integrations.find_by(id: args[:id])
          result = ::Integrations::AgentStorefront::UpdateService.call(integration:, params: args.except(:id))

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
