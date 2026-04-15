# frozen_string_literal: true

module Resolvers
  class OrderFormsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "order_forms:view"

    description "Query order forms"

    argument :customer_id, [ID], required: false
    argument :expiry_date_from, GraphQL::Types::ISO8601Date, required: false
    argument :expiry_date_to, GraphQL::Types::ISO8601Date, required: false
    argument :external_customer_id, [String], required: false
    argument :limit, Integer, required: false
    argument :number, [String], required: false
    argument :order_form_date_from, GraphQL::Types::ISO8601Date, required: false
    argument :order_form_date_to, GraphQL::Types::ISO8601Date, required: false
    argument :owner_id, [ID], required: false
    argument :page, Integer, required: false
    argument :quote_number, [String], required: false
    argument :search_term, String, required: false
    argument :status, [Types::OrderForms::StatusEnum], required: false

    type Types::OrderForms::Object.collection_type, null: false

    def resolve( # rubocop:disable Metrics/ParameterLists
      customer_id: nil,
      expiry_date_from: nil,
      expiry_date_to: nil,
      external_customer_id: nil,
      limit: nil,
      number: nil,
      order_form_date_from: nil,
      order_form_date_to: nil,
      owner_id: nil,
      page: nil,
      quote_number: nil,
      search_term: nil,
      status: nil
    )
      result = OrderFormsQuery.call(
        organization: current_organization,
        pagination: {page:, limit:},
        filters: {
          customer_id:,
          expiry_date_from:,
          expiry_date_to:,
          external_customer_id:,
          number:,
          order_form_date_from:,
          order_form_date_to:,
          owner_id:,
          quote_number:,
          status:
        },
        search_term:
      )

      result.order_forms
    end
  end
end
