# frozen_string_literal: true

module Resolvers
  class PaymentsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "payments:view"

    description "Query payments of an organization"

    argument :invoice_id, String, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false

    type Types::Payments::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, invoice_id: nil)
      result = PaymentsQuery.call(
        organization: current_organization,
        filters: {
          invoice_id:
        },
        pagination: {
          page:,
          limit:
        }
      )

      result.payments
    end
  end
end
