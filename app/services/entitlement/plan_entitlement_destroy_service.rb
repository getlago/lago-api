# frozen_string_literal: true

module Entitlement
  class PlanEntitlementDestroyService < BaseService
    Result = BaseResult[:entitlement]

    def initialize(entitlement:)
      @entitlement = entitlement
      super
    end

    activity_loggable(
      action: "plan.updated",
      record: -> { entitlement&.plan }
    )

    def call
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      previous_webhook_payload = plan_updated_details_payload

      ActiveRecord::Base.transaction do
        entitlement.values.discard_all!
        entitlement.discard!
      end

      SendWebhookJob.perform_after_commit("plan.updated", entitlement.plan)
      send_updated_details_webhook(previous_webhook_payload)

      result.entitlement = entitlement
      result
    end

    private

    attr_reader :entitlement

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
  end
end
