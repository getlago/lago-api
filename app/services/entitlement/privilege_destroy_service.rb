# frozen_string_literal: true

module Entitlement
  class PrivilegeDestroyService < BaseService
    Result = BaseResult[:privilege]

    def initialize(privilege:)
      @privilege = privilege
      super
    end

    activity_loggable(
      action: "feature.updated",
      record: -> { privilege&.feature }
    )

    def call
      return result.not_found_failure!(resource: "privilege") unless privilege

      previous_webhook_payloads = plan_updated_details_payloads(privilege.feature.plans)

      ActiveRecord::Base.transaction do
        privilege.values.discard_all!
        privilege.discard!
      end

      jobs = []
      privilege.feature.plans.each do |plan|
        Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
        jobs << SendWebhookJob.new("plan.updated", plan)
        append_updated_details_job(jobs, plan, previous_webhook_payloads[plan.id])
      end

      after_commit do
        ApplicationJob.perform_all_later(jobs)
        SendWebhookJob.perform_later("feature.updated", privilege.feature)
      end

      result.privilege = privilege
      result
    end

    private

    attr_reader :privilege

    def plan_updated_details_payloads(plans)
      plans.each_with_object({}) do |plan, payloads|
        if plan.organization.webhook_endpoints.exists?
          payloads[plan.id] = Plans::WebhookPayload.snapshot(plan)
        end
      end
    end

    def append_updated_details_job(jobs, plan, previous_payload)
      if previous_payload
        jobs << SendWebhookJob.new(
          "plan.updated_details",
          plan,
          Plans::WebhookPayload.updated_details_options(previous: previous_payload, current_plan: plan)
        )
      end
    end
  end
end
