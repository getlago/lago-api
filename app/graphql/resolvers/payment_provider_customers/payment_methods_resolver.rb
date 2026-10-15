# frozen_string_literal: true

module Resolvers
  module PaymentProviderCustomers
    class PaymentMethodsResolver < Resolvers::BaseResolver
      REQUIRED_PERMISSION = "payment_methods:view"

      description "Query payment methods of a payment connection"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false
      argument :with_deleted, Boolean, required: false

      type Types::PaymentMethods::Object.collection_type, null: false

      def resolve(page: nil, limit: nil, with_deleted: nil)
        result = PaymentMethodsQuery.call(
          organization: object.organization,
          filters: {
            payment_provider_customer_id: object.id,
            with_deleted:
          },
          pagination: {
            page:,
            limit:
          }
        )

        result.payment_methods.includes(:payment_provider)
      end
    end
  end
end
