# frozen_string_literal: true

module Mutations
  module PricingImports
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "UpdatePricingImport"
      description "Saves user edits to a draft pricing import"

      argument :id, ID, required: true
      argument :edited_plan, GraphQL::Types::JSON, required: true

      type Types::PricingImports::Object

      def resolve(id:, edited_plan:)
        pricing_import = current_organization.pricing_imports.find(id)

        result = ::PricingImports::UpdateService.call(
          pricing_import: pricing_import,
          edited_plan: edited_plan
        )

        result.success? ? result.pricing_import : result_error(result)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "pricing_import")
      end
    end
  end
end
