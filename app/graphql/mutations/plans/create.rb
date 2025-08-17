# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:create"

      graphql_name "CreatePlan"
      description "Creates a new Plan"

      input_object_class Types::Plans::CreateInput
      type Types::Plans::Object

      def resolve(entitlements: nil, **args)
        args[:charges].map!(&:to_h)
        args[:fixed_charges]&.map!(&:to_h)

        result = ::Plans::CreateService.call(args.merge(organization_id: current_organization.id))

        return result_error(result) unless result.success?

        plan = result.plan

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
