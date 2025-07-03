# frozen_string_literal: true

module Resolvers
  class PaymentsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "payments:view"

    description "Query payments of an organization"

    argument :external_customer_id, ID, required: false
    argument :invoice_id, ID, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :search_term, String, required: false

    type Types::Payments::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, invoice_id: nil, external_customer_id: nil, search_term: nil)
      result = PaymentsQuery.call(
        organization: current_organization,
        filters: {
          invoice_id:,
          external_customer_id:
        },
        search_term:,
        pagination: {
          page:,
          limit:
        }
      )

      result.payments
    end
  end
end
