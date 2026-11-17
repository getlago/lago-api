# frozen_string_literal: true

module Mutations
  module Integrations
    module Quickbooks
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "organization:integrations:create"

        graphql_name "CreateQuickbooksIntegration"
        description "Create QuickBooks integration"

        input_object_class Types::Integrations::Quickbooks::CreateInput

        type Types::Integrations::Quickbooks

        def resolve(**args)
          result = ::Integrations::Quickbooks::CreateService
            .new(context[:current_user])
            .call(**args.merge(organization_id: current_organization.id))

          result.success? ? result.integration : result_error(result)
        end
      end
    end
  end
end
