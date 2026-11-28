# frozen_string_literal: true

module Entitlement
  class PrivilegeDestroyService < BaseService
    include Concerns::ContractRemovalsConcern

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

      ActiveRecord::Base.transaction do
        # Serializes with the privilege writes and the feature delete, which take the same lock, so
        # nothing is discarded twice or written after the discard.
        # The default scope hides a discarded feature, so it is read without it.
        feature = Feature.unscoped.lock.find_by(id: privilege.entitlement_feature_id)
        return result.not_found_failure!(resource: "privilege") if feature.nil? || feature.discarded? || privilege.reload.discarded?

        privilege.values.discard_all!
        discard_contract_privilege_removals(privilege.organization_id, privilege.id)
        privilege.discard!
      end

      jobs = privilege.feature.plans.map do |plan|
        Utils::ActivityLog.produce_after_commit(plan, "plan.updated")
        SendWebhookJob.new("plan.updated", plan)
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
  end
end
