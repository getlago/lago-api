# frozen_string_literal: true

module Resolvers
  class ProductResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = "products:view"

    description "Query a single product of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the product"

    type Types::Products::Object, null: true

    def resolve(id: nil)
      current_organization.products.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "product")
    end
  end
end
