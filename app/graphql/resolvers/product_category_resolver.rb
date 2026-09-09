# frozen_string_literal: true

module Resolvers
  class ProductCategoryResolver < Resolvers::BaseResolver
    include RequiresProductCatalog
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "product_categories:view"

    description "Query a single product_category of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the product_category"

    type Types::ProductCategories::Object, null: true

    def resolve(id: nil)
      current_organization.product_categories.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "product_category")
    end
  end
end
