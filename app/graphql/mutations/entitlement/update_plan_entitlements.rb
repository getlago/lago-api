# frozen_string_literal: true

module Mutations
  module Entitlement
    class UpdatePlanEntitlements < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      description "Updates plan entitlements"

      argument :plan_id, ID, required: true

      argument :entitlements, [Types::Entitlement::PlanEntitlementInput], required: true

      type Types::Entitlement::PlanEntitlementObject.collection_type

      def resolve(**args)
        plan = current_organization.plans.parents.find_by(id: args[:plan_id])

        result = ::Entitlement::PlanEntitlementsUpdateService.call(
          organization: current_organization,
          plan:,
          entitlements_params: args[:entitlements].map do |ent|
            [
              ent.feature_code,
              ent.privileges&.map { [it.privilege_code, it.value] }.to_h
            ]
          end.to_h,
          partial: false
        )

        result.success? ? result.entitlements : result_error(result)
      end
    end
  end
end
