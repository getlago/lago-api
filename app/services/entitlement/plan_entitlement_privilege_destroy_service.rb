# frozen_string_literal: true

module Entitlement
  class PlanEntitlementPrivilegeDestroyService < BaseService
    Result = BaseResult[:entitlement]

    def initialize(entitlement:, privilege_code:)
      @entitlement = entitlement
      @privilege_code = privilege_code
      super
    end

    activity_loggable(
      action: "plan.updated",
      record: -> { entitlement&.plan }
    )

    def call
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      entitlement_value = find_entitlement_value
      return result.not_found_failure!(resource: "privilege") unless entitlement_value

      previous_webhook_payload = plan_updated_details_payload

      entitlement_value.discard!

      SendWebhookJob.perform_after_commit("plan.updated", entitlement.plan)
      send_updated_details_webhook(previous_webhook_payload)

      # NOTE: reload the entitlement with all the associations required to serialize it
      result.entitlement = Entitlement.includes(:feature, values: :privilege).find_by(id: entitlement.id)
      result
    end

    private

    attr_reader :entitlement, :privilege_code

    def plan_updated_details_payload
      if entitlement.plan.organization.webhook_endpoints.exists?
        Plans::WebhookPayload.snapshot(entitlement.plan)
      end
    end

    def send_updated_details_webhook(previous_payload)
      if previous_payload
        SendWebhookJob.perform_after_commit(
          "plan.updated_details",
          entitlement.plan,
          Plans::WebhookPayload.updated_details_options(previous: previous_payload, current_plan: entitlement.plan)
        )
      end
    end

    def find_entitlement_value
      entitlement.values.joins(:privilege).find_by(privilege: {code: privilege_code})
    end
  end
end
