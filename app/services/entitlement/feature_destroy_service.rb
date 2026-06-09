# frozen_string_literal: true

module Entitlement
  class FeatureDestroyService < BaseService
    Result = BaseResult[:feature]

    def initialize(feature:)
      @feature = feature
      super
    end

    activity_loggable(
      action: "feature.deleted",
      record: -> { result.feature }
    )

    def call
      return result.not_found_failure!(resource: "feature") unless feature

      plans = feature.plans.to_a
      previous_webhook_payloads = plan_updated_details_payloads(plans)

      ActiveRecord::Base.transaction do
        feature.entitlement_values.discard_all!
        feature.entitlements.discard_all!
        feature.privileges.discard_all!
        feature.discard!
      end

      jobs = []
      plans.each do |plan|
        Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
        jobs << SendWebhookJob.new("plan.updated", plan)
        append_updated_details_job(jobs, plan, previous_webhook_payloads[plan.id])
      end

      after_commit do
        ApplicationJob.perform_all_later(jobs)
        SendWebhookJob.perform_later("feature.deleted", feature)
      end

      result.feature = feature
      result
    end

    private

    attr_reader :feature

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
