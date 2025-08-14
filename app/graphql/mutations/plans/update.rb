# frozen_string_literal: true

module Mutations
  module Plans
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "UpdatePlan"
      description "Updates an existing Plan"

      input_object_class Types::Plans::UpdateInput
      type Types::Plans::Object

      def resolve(entitlements: nil, **args)
        args[:charges].map!(&:to_h)
        args[:fixed_charges]&.map!(&:to_h)
        plan = context[:current_user].plans.find_by(id: args[:id])

        result = ::Plans::UpdateService.call(plan:, params: args)

        return result_error(result) unless result.success?

        if entitlements.present? && License.premium?
          result = ::Entitlement::PlanEntitlementsUpdateService.call(
            organization: plan.organization,
            plan:,
            entitlements_params: Utils::Entitlement.convert_gql_input_to_params(entitlements),
            partial: false
          )
        end

        result.success? ? plan.reload : result_error(result)
      end
    end
  end
end
