# frozen_string_literal: true

module Mutations
  module CatalogPlans
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "UpdateCatalogPlan"
      description "Updates an existing catalog plan"

      input_object_class Types::CatalogPlans::UpdateInput
      type Types::Plans::Object

      def resolve(**args)
        catalog_plan = current_organization.catalog_plans.find_by(id: args[:id])

        result = ::CatalogPlans::UpdateService.call(catalog_plan:, params: args.except(:id))

        result.success? ? result.catalog_plan : result_error(result)
      end
    end
  end
end
