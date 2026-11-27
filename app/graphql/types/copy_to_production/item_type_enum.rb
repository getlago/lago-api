# frozen_string_literal: true

module Types
  module CopyToProduction
    class ItemTypeEnum < Types::BaseEnum
      graphql_name "CopyToProductionItemTypeEnum"
      description "Item types a sandbox can move to its production organization"

      ::CopyToProduction::Items::TYPES.each_key do |item_type|
        value item_type
      end
    end
  end
end
