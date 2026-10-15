# frozen_string_literal: true

module Resolvers
  class ProductFilterResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_filters:view"

    description "Query a single product filter of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the product filter"

    type Types::ProductFilters::Object, null: true

    def resolve(id: nil)
      current_organization.product_filters.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "product_filter")
    end
  end
end
