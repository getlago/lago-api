# frozen_string_literal: true

module Resolvers
  class SubscriptionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "subscriptions:view"

    description "Query subscriptions of an organization"

    argument :external_customer_id, String, required: false
    argument :limit, Integer, required: false
    argument :overriden, Boolean, required: false
    argument :page, Integer, required: false
    argument :plan_code, String, required: false
    argument :search_term, String, required: false
    argument :status, [Types::Subscriptions::StatusTypeEnum], required: false

    type Types::Subscriptions::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, plan_code: nil, status: nil, external_customer_id: nil, overriden: nil, search_term: nil)
      # In FE we include next subscription in the list, so we need to exclude subscriptions with previous subscription from the list
      result = SubscriptionsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {plan_code:, status:, external_customer_id:, overriden:, exclude_next_subscriptions: true},
        search_term:
      )

      result.subscriptions
    end
  end
end
