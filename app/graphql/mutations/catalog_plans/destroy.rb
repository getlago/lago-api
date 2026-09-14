# frozen_string_literal: true

module Mutations
  module CatalogPlans
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:delete"

      graphql_name "DestroyCatalogPlan"
      description "Deletes a catalog plan"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        catalog_plan = current_organization.catalog_plans.find_by(id:)
        result = ::CatalogPlans::DestroyService.call(catalog_plan:)

        result.success? ? result.catalog_plan : result_error(result)
      end
    end
  end
end
