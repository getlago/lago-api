# frozen_string_literal: true

module Types
  module Connections
    class CategoryEnum < Types::BaseEnum
      graphql_name "ConnectionCategoryEnum"

      BillingObjectConnection::CATEGORIES.each_key do |category|
        value category
      end
    end
  end
end
