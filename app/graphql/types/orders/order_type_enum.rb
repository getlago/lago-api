# frozen_string_literal: true

module Types
  module Orders
    class OrderTypeEnum < Types::BaseEnum
      Order::ORDER_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
