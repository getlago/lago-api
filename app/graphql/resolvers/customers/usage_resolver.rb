# frozen_string_literal: true

module Resolvers
  module Customers
    class UsageResolver < Resolvers::BaseResolver
      include AuthenticableApiUser

      description 'Query the usage of the customer on the current billing period'

      argument :customer_id, type: ID, required: false

      type Types::Invoices::Usage, null: false

      def resolve(customer_id:)
        result = Invoices::CustomerUsageService
          .new(context[:current_user], customer_id: customer_id)
          .usage

        result.success? ? result.usage : result_error(result)
      end
    end
  end
end
