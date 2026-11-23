# frozen_string_literal: true

module Types
  module CopyToProduction
    class Preview < Types::BaseObject
      graphql_name "CopyToProductionPreview"
      description "What moving an item to live mode would copy, reuse or refuse"

      field :blocking_reason, Types::CopyToProduction::BlockingReasonEnum, null: true
      field :copied_items, [Types::CopyToProduction::Item], null: false, description: "Sandbox items to copy, the requested item last"
      field :missing_parent, Types::CopyToProduction::Item, null: true, description: "Sandbox parent to copy to production first"
      field :reused_items, [Types::CopyToProduction::Item], null: false, description: "Production items reused by code"
    end
  end
end
