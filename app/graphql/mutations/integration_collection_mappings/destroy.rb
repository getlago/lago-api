# frozen_string_literal: true

module Mutations
  module IntegrationCollectionMappings
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'DestroyIntegrationCollectionMapping'
      description 'Destroy an integration collection mapping'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        integration_collection_mapping = ::IntegrationCollectionMappings::BaseCollectionMapping
          .joins(:integration)
          .where(id:)
          .where(integration: { organization: current_organization }).first

        return not_found_error(resource: 'integration_collection_mapping') unless integration_collection_mapping

        result = ::IntegrationCollectionMappings::DestroyService.call(integration_collection_mapping:)

        result.success? ? result.integration_collection_mapping : result_error(result)
      end
    end
  end
end
