# frozen_string_literal: true

module Resolvers
  module IntegrationMappings
    class NetsuiteMappingResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'organization:integrations:view'

      description 'Query a single integration mapping'

      argument :id, ID, required: true, description: 'Unique ID of the integration mappings'

      type Types::IntegrationMappings::Netsuite::Object, null: true

      def resolve(id: nil)
        mapping = ::IntegrationMappings::NetsuiteMapping
          .joins(:integration)
          .where(id:, integration: { organization: current_organization }).first

        return not_found_error(resource: 'integration_mapping') unless mapping

        mapping
      end
    end
  end
end
