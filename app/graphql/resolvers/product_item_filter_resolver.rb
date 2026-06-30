# frozen_string_literal: true

module Resolvers
  class ProductItemFilterResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_items:view"

    description "Query a single product item filter of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the product item filter"

    type Types::ProductItemFilters::Object, null: true

    def resolve(id: nil)
      current_organization.product_item_filters.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "product_item_filter")
    end
  end
end
