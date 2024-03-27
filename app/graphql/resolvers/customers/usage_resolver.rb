# frozen_string_literal: true

module Resolvers
  module Customers
    class UsageResolver < Resolvers::BaseResolver
      include AuthenticableApiUser

      description "Query the usage of the customer on the current billing period"

      argument :customer_id, type: ID, required: false
      argument :subscription_id, type: ID, required: true

      type Types::Customers::Usage::Current, null: false

      def resolve(customer_id:, subscription_id:)
        result = Invoices::CustomerUsageService.call(context[:current_user], customer_id:, subscription_id:)

        result.success? ? result.usage : result_error(result)
      end
    end
  end
end
