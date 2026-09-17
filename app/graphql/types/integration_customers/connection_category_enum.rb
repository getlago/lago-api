# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class ConnectionCategoryEnum < Types::BaseEnum
      graphql_name "IntegrationConnectionCategoryEnum"

      ::IntegrationCustomers::BaseCustomer::CATEGORIES.each_key do |category|
        value category
      end
    end
  end
end
