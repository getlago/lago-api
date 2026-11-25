# frozen_string_literal: true

module Types
  module CopyToProduction
    class Preview < Types::BaseObject
      graphql_name "CopyToProductionPreview"
      description "What moving an item to live mode would copy, reuse or refuse"

      field :blocking_reason, Types::CopyToProduction::BlockingReasonEnum, null: true
      field :copied_items, [Types::CopyToProduction::Item], null: false, description: "Sandbox items to copy, the requested item last"
      field :missing_parent, Types::CopyToProduction::Item, null: true, description: "Sandbox parent to copy to production first"
      field :refusal_code, String, null: true,
        description: "With copy_to_production_item_refused, the code in the details of the copy's error"
      field :refusal_field, String, null: true,
        description: "With copy_to_production_item_refused, the key of that code in the details: a field, or a resource"
      field :refused_item, Types::CopyToProduction::Item, null: true,
        description: "Sandbox item that refuses the copy: an item to copy, or the requested item when it is live"
      field :reused_items, [Types::CopyToProduction::Item], null: false, description: "Production items reused by code"

      # Fields are named as in the details of a GraphQL error.
      def refusal_field
        object.refusal_field&.camelize(:lower)
      end
    end
  end
end
