# frozen_string_literal: true

module Types
  module CopyToProduction
    class CopyInput < BaseInputObject
      graphql_name "CopyToProductionInput"
      description "Copy to production input arguments"

      argument :id, ID, required: true, description: "ID of the item in the sandbox"
      argument :item_type, Types::CopyToProduction::CopyableItemTypeEnum, required: true
    end
  end
end
