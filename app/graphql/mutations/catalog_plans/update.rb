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
        args[:amount_currency] = args.delete(:currency) if args.key?(:currency)
        plan = current_organization.plans.parents.product_catalog.find_by(id: args[:id])

        result = ::Plans::UpdateService.call(plan:, params: args.except(:id))

        return result.plan if result.success?

        # The catalog surface exposes amount_currency as `currency`.
        if result.error.is_a?(BaseService::ValidationFailure) && result.error.messages.key?(:amount_currency)
          messages = result.error.messages.except(:amount_currency).merge(currency: result.error.messages[:amount_currency])
          return validation_error(messages:)
        end

        result_error(result)
      end
    end
  end
end
