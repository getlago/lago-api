# frozen_string_literal: true

module Types
  module Products
    class ProductTypeEnum < Types::BaseEnum
      Product::PRODUCT_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
