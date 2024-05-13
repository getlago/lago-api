# frozen_string_literal: true

module Resolvers
  class IntegrationMappingsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'organization:integrations:view'

    description 'Query netsuite integration mappings'

    argument :integration_id, ID, required: false
    argument :limit, Integer, required: false
    argument :mappable_type, Types::IntegrationMappings::MappableTypeEnum, required: false
    argument :page, Integer, required: false

    type Types::IntegrationMappings::Object.collection_type, null: true

    def resolve(page: nil, limit: nil, integration_id: nil, mappable_type: nil)
      result = ::IntegrationMappingsQuery.call(
        organization: current_organization,
        pagination: BaseQuery::Pagination.new(page:, limit:),
        filters: BaseQuery::Filters.new({integration_id:, mappable_type:}),
      )

      result.integration_mappings
    end
  end
end
