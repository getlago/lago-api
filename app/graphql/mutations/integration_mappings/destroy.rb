# frozen_string_literal: true

module Mutations
  module IntegrationMappings
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DestroyIntegrationMapping'
      description 'Destroy an integration mapping'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        integration_mapping = ::IntegrationMappings::BaseMapping
          .joins(:integration)
          .where(id:)
          .where(integration: { organization: current_organization }).first

        return not_found_error(resource: 'integration_mapping') unless integration_mapping

        result = ::IntegrationMappings::DestroyService.call(integration_mapping:)

        result.success? ? result.integration_mapping : result_error(result)
      end
    end
  end
end
