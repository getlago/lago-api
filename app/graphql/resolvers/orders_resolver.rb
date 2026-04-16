# frozen_string_literal: true

module Resolvers
  class OrdersResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "orders:view"

    description "Query orders"

    argument :external_customer_id, ID, required: false
    argument :limit, Integer, required: false
    argument :order_type, [Types::Orders::OrderTypeEnum], required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false
    argument :status, [Types::Orders::StatusEnum], required: false

    type Types::Orders::Object.collection_type, null: false

    def resolve(external_customer_id: nil, status: nil, order_type: nil, page: nil, limit: nil, search_term: nil)
      result = OrdersQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {
          status:,
          order_type:,
          external_customer_id:
        },
        search_term:
      )

      result.orders
    end
  end
end
