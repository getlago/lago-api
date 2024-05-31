# frozen_string_literal: true

module Resolvers
  class IntegrationCollectionMappingsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'organization:integrations:view'

    description 'Query integration collection mappings'

    argument :integration_id, ID, required: false
    argument :limit, Integer, required: false
    argument :mapping_type, Types::IntegrationCollectionMappings::MappingTypeEnum, required: false
    argument :page, Integer, required: false

    type Types::IntegrationCollectionMappings::Object.collection_type, null: true

    def resolve(page: nil, limit: nil, integration_id: nil, mapping_type: nil)
      result = ::IntegrationCollectionMappingsQuery.call(
        organization: current_organization,
        pagination: BaseQuery::Pagination.new(page:, limit:),
        filters: BaseQuery::Filters.new({integration_id:, mapping_type:})
      )

      result.integration_collection_mappings
    end
  end
end
