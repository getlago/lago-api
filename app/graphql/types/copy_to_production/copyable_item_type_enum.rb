# frozen_string_literal: true

module Types
  module CopyToProduction
    class CopyableItemTypeEnum < Types::BaseEnum
      graphql_name "CopyToProductionCopyableItemTypeEnum"
      description "Item types a user can copy from a sandbox to its production organization"

      ::CopyToProduction::Items::TYPES.each_key do |item_type|
        value item_type if ::CopyToProduction::Items.copyable?(item_type)
      end
    end
  end
end
