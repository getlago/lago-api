# frozen_string_literal: true

module Mutations
  module Integrations
    module Quickbooks
      class VerifyConnection < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:update"

        graphql_name "VerifyQuickbooksIntegrationConnection"
        description "Checks that the QuickBooks connection still points at the company of the integration"

        input_object_class Types::Integrations::Quickbooks::VerifyConnectionInput

        type Types::Integrations::Quickbooks

        def resolve(**args)
          integration = current_organization.integrations.find_by(id: args[:id])
          result = ::Integrations::Quickbooks::VerifyConnectionService.call(integration:)

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
