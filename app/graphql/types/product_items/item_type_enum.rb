# frozen_string_literal: true

module Types
  module ProductItems
    class ItemTypeEnum < Types::BaseEnum
      graphql_name "ProductItemTypeEnum"

      ProductItem::ITEM_TYPES.keys.each do |type|
        value type
      end
    end
  end
end
