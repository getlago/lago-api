# frozen_string_literal: true

module Mutations
  module PricingImports
    class Confirm < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "ConfirmPricingImport"
      description "Confirms a draft pricing import and enqueues execution"

      argument :id, ID, required: true

      type Types::PricingImports::Object

      def resolve(id:)
        pricing_import = current_organization.pricing_imports.find(id)

        result = ::PricingImports::ConfirmService.call(pricing_import: pricing_import)

        result.success? ? result.pricing_import : result_error(result)
      rescue ActiveRecord::RecordNotFound
        not_found_error(resource: "pricing_import")
      end
    end
  end
end
