# frozen_string_literal: true

module Resolvers
  module Customers
    class ForecastResolver < Resolvers::BaseResolver
      include AuthenticableApiUser

      description 'Query the forecast of customer usage'

      argument :customer_id, type: ID, required: false

      type Types::Invoices::Forecast, null: false

      def resolve(customer_id:)
        result = Invoices::ForecastService.new(context[:current_user])
          .forecast(customer_id: customer_id)

        result.success? ? result.invoice : result_error(result)
      end
    end
  end
end
