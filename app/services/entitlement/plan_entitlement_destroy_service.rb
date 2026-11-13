# frozen_string_literal: true

module Entitlement
  class PlanEntitlementDestroyService < BaseService
    include ::Entitlement::Concerns::OwnerLockConcern

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

      # NOTE: The entitlement is not re-read under the lock: a concurrent delete of the same entitlement still succeeds.
      ActiveRecord::Base.transaction do
        lock_plan!(entitlement.plan)
        entitlement.values.discard_all!
        entitlement.discard!
      end

      SendWebhookJob.perform_after_commit("plan.updated", entitlement.plan)

      result.entitlement = entitlement
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :entitlement
  end
end
