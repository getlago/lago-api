# frozen_string_literal: true

module Resolvers
  module IntegrationMappings
    class NetsuiteMappingsResolver < Resolvers::BaseResolver
      include AuthenticableApiUser
      include RequiredOrganization

      description 'Query netsuite integration mappings'

      argument :integration_id, ID, required: false
      argument :limit, Integer, required: false
      argument :mappable_type, String, required: false
      argument :page, Integer, required: false

      type Types::IntegrationMappings::Netsuite::Object.collection_type, null: true

      def resolve(page: nil, limit: nil, integration_id: nil, mappable_type: nil)
        result = ::IntegrationMappings::NetsuiteMappingsQuery.call(
          organization: current_organization,
          pagination: BaseQuery::Pagination.new(page:, limit:),
          filters: BaseQuery::Filters.new({ integration_id:, mappable_type: }),
        )

        result.netsuite_mappings
      end
    end
  end
end
