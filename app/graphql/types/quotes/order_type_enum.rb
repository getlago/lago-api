# frozen_string_literal: true

module Types
  module Quotes
    class OrderTypeEnum < Types::BaseEnum
      graphql_name "QuoteOrderTypeEnum"

      Quote::ORDER_TYPES.keys.each do |order_type|
        value order_type
      end
    end
  end
end
