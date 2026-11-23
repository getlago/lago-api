# frozen_string_literal: true

module Mutations
  module Integrations
    module Quickbooks
      class Update < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "UpdateQuickbooksIntegration"
        description "Update QuickBooks integration"

        input_object_class Types::Integrations::Quickbooks::UpdateInput

        type Types::Integrations::Quickbooks

        def resolve(**args)
          integration = current_organization.integrations.find_by(id: args[:id])
          result = ::Integrations::Quickbooks::UpdateService.call(integration:, params: args)

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
