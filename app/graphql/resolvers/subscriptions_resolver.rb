# frozen_string_literal: true

module Resolvers
  class SubscriptionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = 'subscriptions:view'

    description 'Query subscriptions of an organization'

    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :plan_code, String, required: false
    argument :status, [Types::Subscriptions::StatusTypeEnum], required: false

    type Types::Subscriptions::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, plan_code: nil, status: nil)
      result = SubscriptionsQuery.call(
        organization: current_organization,
        pagination: BaseQuery::Pagination.new(page:, limit:),
        filters: BaseQuery::Filters.new({ plan_code:, status: }),
      )

      result.subscriptions
    end
  end
end
