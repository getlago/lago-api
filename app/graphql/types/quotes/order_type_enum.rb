# frozen_string_literal: true

module Types
  module Quotes
    class OrderTypeEnum < Types::BaseEnum
      Quote::ORDER_TYPES.keys.each do |order_type|
        value order_type
      end
    end
  end
end
