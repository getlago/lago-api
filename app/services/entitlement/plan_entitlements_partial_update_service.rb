# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsPartialUpdateService < PlanEntitlementsBaseService
    Result = BaseResult[:entitlements]

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "plan") unless plan

      handle_validation_errors do
        ActiveRecord::Base.transaction do
          update_entitlements
        end

        # NOTE: The webhooks is sent even if no changes were made to the plan
        SendWebhookJob.perform_after_commit("plan.updated", plan)

        result.entitlements = plan.entitlements.reload.includes(:feature, values: :privilege)
        result
      end
    end

    private

    def update_entitlements
      return if entitlements_params.blank?

      entitlements_params.each do |feature_code, privilege_values|
        feature = organization.features.includes(:privileges).find { it.code == feature_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Feature") unless feature

        # Find existing entitlement or create new one
        entitlement = plan.entitlements.includes(:values).find { it.entitlement_feature_id == feature.id }

        if entitlement.nil?
          entitlement = Entitlement.create!(
            organization: organization,
            feature: feature,
            plan: plan
          )
        end

        update_entitlement_values(entitlement, feature, privilege_values) if privilege_values.present?
      end
    end
  end
end
