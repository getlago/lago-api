# frozen_string_literal: true

module Types
  module CopyToProduction
    class ItemTypeEnum < Types::BaseEnum
      graphql_name "CopyToProductionItemTypeEnum"
      description "Item types of Copy to production, including those only copied along with another item"

      ::CopyToProduction::Items::TYPES.each_key do |item_type|
        value item_type
      end
    end
  end
end
