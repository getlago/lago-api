# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsCreateService < PlanEntitlementsBaseService
    Result = BaseResult[:entitlements]

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "plan") unless plan

      handle_validation_errors do
        ActiveRecord::Base.transaction do
          # Delete all existing entitlements and their values for this plan
          delete_existing_entitlements

          # Create new entitlements based on the payload
          create_entitlements
        end

        SendWebhookJob.perform_after_commit("plan.updated", plan)

        result.entitlements = plan.entitlements.includes(:feature, values: :privilege)
        result
      end
    end

    private

    def delete_existing_entitlements
      EntitlementValue.where(entitlement: plan.entitlements).discard_all!
      plan.entitlements.discard_all!
    end

    def create_entitlements
      return if entitlements_params.blank?

      entitlements_params.each do |feature_code, privilege_values|
        feature = organization.features.includes(:privileges).find { it.code == feature_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Feature") unless feature

        entitlement = Entitlement.create!(
          organization: organization,
          feature: feature,
          plan: plan
        )

        create_entitlement_values(entitlement, feature, privilege_values) if privilege_values.present?
      end
    end
  end
end
