# frozen_string_literal: true

module Resolvers
  class IntegrationItemsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'organization:integrations:view'

    description 'Query integration items of an integration'

    argument :integration_id, ID, required: true
    argument :item_type, Types::IntegrationItems::ItemTypeEnum, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::IntegrationItems::Object.collection_type, null: false

    def resolve(integration_id:, page: nil, limit: nil, search_term: nil, item_type: nil)
      integration = current_organization.integrations.where(id: integration_id).first

      return not_found_error(resource: 'integration') unless integration

      query = ::IntegrationItemsQuery.new(organization: current_organization)
      result = query.call(
        integration_id:,
        search_term:,
        page:,
        limit:,
        filters: {
          item_type:
        },
      )

      result.integration_items
    end
  end
end
