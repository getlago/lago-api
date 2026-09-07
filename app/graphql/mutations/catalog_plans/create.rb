# frozen_string_literal: true

module Mutations
  module CatalogPlans
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:create"

      graphql_name "CreateCatalogPlan"
      description "Creates a new catalog plan"

      input_object_class Types::CatalogPlans::CreateInput
      type Types::Plans::Object

      def resolve(**args)
        result = ::CatalogPlans::CreateService.call(args.merge(organization_id: current_organization.id))

        result.success? ? result.catalog_plan : result_error(result)
      end
    end
  end
end
