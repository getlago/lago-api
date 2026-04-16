# frozen_string_literal: true

module Resolvers
  class OrderFormsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "order_forms:view"

    description "Query order forms"

    argument :external_customer_id, ID, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false
    argument :status, [Types::OrderForms::StatusEnum], required: false

    type Types::OrderForms::Object.collection_type, null: false

    def resolve(external_customer_id: nil, status: nil, page: nil, limit: nil, search_term: nil)
      result = OrderFormsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {
          status:,
          external_customer_id:
        },
        search_term:
      )

      result.order_forms
    end
  end
end
