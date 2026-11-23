# frozen_string_literal: true

module Types
  module CopyToProduction
    class BlockingReasonEnum < Types::BaseEnum
      graphql_name "CopyToProductionBlockingReasonEnum"
      description "Why production refuses to receive an item, as the error code the copy would answer"

      value "value_already_exist", description: "Production already has an item with this code"
      value "organization_inactive", description: "Production is waiting for a payment method"
      value "copy_to_production_admin_only", description: "The user is not an admin of production"
      value "copy_to_production_parent_missing", description: "The item's parent must be copied to production first"
      value "copy_to_production_item_unsupported", description: "This item cannot be copied to production"
    end
  end
end
