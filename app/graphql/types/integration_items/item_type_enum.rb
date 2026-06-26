# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module IntegrationItems
    class ItemTypeEnum < Types::BaseEnum
      graphql_name "IntegrationItemTypeEnum"

      IntegrationItem::ITEM_TYPES.each do |type|
        value type
      end
    end
  end
end
