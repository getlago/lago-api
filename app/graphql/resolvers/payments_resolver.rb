# frozen_string_literal: true

module Resolvers
  class PaymentsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "payments:view"

    description "Query payments of an organization"

    argument :amount_from, GraphQL::Types::BigInt, required: false
    argument :amount_to, GraphQL::Types::BigInt, required: false
    argument :created_at_from, GraphQL::Types::ISO8601Date, required: false
    argument :created_at_to, GraphQL::Types::ISO8601Date, required: false
    argument :currency, Types::CurrencyEnum, required: false
    argument :external_customer_id, ID, required: false
    argument :invoice_id, ID, required: false
    argument :invoice_number, String, required: false
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :payable_type, [Types::Payments::PayableTypeEnum], required: false
    argument :payment_method_type, [Types::Payments::PaymentMethodTypeEnum], required: false
    argument :payment_provider_type, [Types::PaymentProviders::ProviderTypeEnum], required: false
    argument :payment_status, [Types::Payments::PayablePaymentStatusEnum], required: false
    argument :payment_type, [Types::Payments::PaymentTypeEnum], required: false
    argument :receipt_number, String, required: false
    argument :search_term, String, required: false

    type Types::Payments::Object.collection_type, null: false

    def resolve(page: nil, limit: nil, search_term: nil, **filters)
      result = PaymentsQuery.call(
        organization: current_organization,
        filters:,
        search_term:,
        pagination: {
          page:,
          limit:
        }
      )

      result.success? ? result.payments : result_error(result)
    end
  end
end
