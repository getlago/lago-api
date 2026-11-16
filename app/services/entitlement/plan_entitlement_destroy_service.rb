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

      ActiveRecord::Base.transaction do
        lock_plan!(entitlement.plan)

        # The entitlement was loaded before the lock: a concurrent delete may have discarded it since.
        # No reload: the caller serializes the values already loaded on the entitlement.
        unless ::Entitlement::Entitlement.where(id: entitlement.id).exists?
          result.not_found_failure!(resource: "entitlement").raise_if_error!
        end

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
