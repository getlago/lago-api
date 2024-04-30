# frozen_string_literal: true

module Resolvers
  module IntegrationCollectionMappings
    class NetsuiteCollectionMappingResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:view'

      description 'Query a single integration collection mapping'

      argument :id, ID, required: true, description: 'Unique ID of the integration collection mappings'

      type Types::IntegrationCollectionMappings::Netsuite::Object, null: true

      def resolve(id: nil)
        mapping = ::IntegrationCollectionMappings::NetsuiteCollectionMapping
          .joins(:integration)
          .where(id:, integration: { organization: current_organization }).first

        return not_found_error(resource: 'integration_collection_mapping') unless mapping

        mapping
      end
    end
  end
end
