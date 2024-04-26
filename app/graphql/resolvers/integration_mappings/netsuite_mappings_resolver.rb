# frozen_string_literal: true

module Resolvers
  module IntegrationMappings
    class NetsuiteMappingsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      description 'Query netsuite integration mappings'

      argument :integration_id, ID, required: false
      argument :limit, Integer, required: false
      argument :mappable_type, Types::IntegrationMappings::Netsuite::MappableTypeEnum, required: false
      argument :page, Integer, required: false
      argument :search_term, String, required: false

      type Types::IntegrationMappings::Netsuite::Object.collection_type, null: true

      def resolve(page: nil, limit: nil, integration_id: nil, mappable_type: nil, search_term: nil)
        query = ::IntegrationMappings::NetsuiteMappingsQuery.new(organization: current_organization)
        result = query.call(
          search_term:,
          integration_id:,
          page:,
          limit:,
          filters: {
            mappable_type:,
          },
        )

        result.netsuite_mappings
      end
    end
  end
end
