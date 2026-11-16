# frozen_string_literal: true

module Entitlement
  class PlanEntitlementPrivilegeDestroyService < BaseService
    include ::Entitlement::Concerns::OwnerLockConcern

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

      ActiveRecord::Base.transaction do
        lock_plan!(entitlement.plan)

        # The value was loaded before the lock: a concurrent delete may have discarded it since.
        result.not_found_failure!(resource: "privilege").raise_if_error! if entitlement_value.reload.discarded?

        entitlement_value.discard!
      end

      SendWebhookJob.perform_after_commit("plan.updated", entitlement.plan)

      # NOTE: reload the entitlement with all the associations required to serialize it
      result.entitlement = Entitlement.includes(:feature, values: :privilege).find_by(id: entitlement.id)
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :entitlement, :privilege_code

    def find_entitlement_value
      entitlement.values.joins(:privilege).find_by(privilege: {code: privilege_code})
    end
  end
end
