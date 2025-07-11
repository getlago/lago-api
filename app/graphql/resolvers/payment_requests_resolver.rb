# frozen_string_literal: true

module Resolvers
  class PaymentRequestsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "payment_requests:view"

    description "Query payment requests of an organization"

    argument :external_customer_id, String, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :payment_status, Types::Invoices::PaymentStatusTypeEnum, required: false

    type Types::PaymentRequests::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, external_customer_id: nil, payment_status: nil)
      result = PaymentRequestsQuery.call(
        organization: current_organization,
        filters: {
          external_customer_id:,
          payment_status:
        },
        pagination: {
          page:,
          limit:
        }
      )

      result.payment_requests
    end
  end
end
