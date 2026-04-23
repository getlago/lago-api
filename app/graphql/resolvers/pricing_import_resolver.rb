# frozen_string_literal: true

module Resolvers
  class PricingImportResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query a single pricing import of an organization"

    argument :id, ID, required: true

    type Types::PricingImports::Object, null: true

    def resolve(id:)
      current_organization.pricing_imports.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "pricing_import")
    end
  end
end
