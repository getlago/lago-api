# frozen_string_literal: true

module Resolvers
  module IntegrationCollectionMappings
    class NetsuiteCollectionMappingsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      description 'Query netsuite integration collection mappings'

      argument :integration_id, ID, required: false
      argument :limit, Integer, required: false
      argument :mapping_type, String, required: false
      argument :page, Integer, required: false

      type Types::IntegrationCollectionMappings::Netsuite::Object.collection_type, null: true

      def resolve(page: nil, limit: nil, integration_id: nil, mapping_type: nil)
        result = ::IntegrationCollectionMappings::NetsuiteCollectionMappingsQuery.call(
          organization: current_organization,
          pagination: BaseQuery::Pagination.new(page:, limit:),
          filters: BaseQuery::Filters.new({ integration_id:, mapping_type: }),
        )

        result.netsuite_collection_mappings
      end
    end
  end
end
