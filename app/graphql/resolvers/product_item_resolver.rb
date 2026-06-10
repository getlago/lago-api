# frozen_string_literal: true

module Resolvers
  class ProductItemResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_items:view"

    description "Query a single product item of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the product item"

    type Types::ProductItems::Object, null: true

    def resolve(id: nil)
      current_organization.product_items.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "product_item")
    end
  end
end
