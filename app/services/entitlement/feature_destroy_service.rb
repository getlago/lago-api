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

      ActiveRecord::Base.transaction do
        # Serializes with Entitlement::PrivilegeCreateService, so no kept privilege is added to a discarded feature.
        feature.lock!
        return result.not_found_failure!(resource: "feature") if feature.discarded?

        feature.entitlement_values.discard_all!
        feature.entitlements.discard_all!
        discard_contract_removals
        feature.privileges.discard_all!
        feature.discard!
      end

      jobs = []
      plans.each do |plan|
        Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
        jobs << SendWebhookJob.new("plan.updated", plan)
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

    # Only contract removals are discarded: subscription removals keep their existing behaviour.
    def discard_contract_removals
      now = Time.current
      contract_removals = SubscriptionFeatureRemoval.where(organization_id: feature.organization_id).where.not(contract_id: nil)

      contract_removals
        .where(entitlement_feature_id: feature.id)
        .or(contract_removals.where(entitlement_privilege_id: feature.privileges.select(:id)))
        .update_all(deleted_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
