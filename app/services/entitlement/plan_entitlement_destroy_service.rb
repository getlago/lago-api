# frozen_string_literal: true

module Entitlement
  class PlanEntitlementDestroyService < BaseService
    include ::Entitlement::Concerns::OwnerLockConcern

    Result = BaseResult[:entitlement]

    def initialize(entitlement:)
      @entitlement = entitlement
      super
    end

    # A catalog plan gets no plan.updated event: with the entitlement_events flag, it gets a plan_entitlement.deleted
    # activity log and webhook, and without it nothing is sent.
    activity_loggable(
      action: "plan.updated",
      record: -> { entitlement && owner },
      condition: -> { entitlement && !catalog_plan? }
    )

    def call
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      ActiveRecord::Base.transaction do
        lock_plan!(owner)
        if catalog_plan?
          reload_under_lock!
          values_before = ::V2::PlanEntitlementSerializer.new(entitlement).serialize[:values] if entitlement_events?
        else
          # The entitlement was loaded before the lock: a concurrent delete may have discarded it since.
          # No reload: the caller serializes the values already loaded on the entitlement.
          unless ::Entitlement::Entitlement.where(id: entitlement.id).exists?
            result.not_found_failure!(resource: "entitlement").raise_if_error!
          end
        end

        entitlement.values.discard_all!
        entitlement.discard!

        if catalog_plan?
          send_deleted_events(values_before) if entitlement_events?
        else
          SendWebhookJob.perform_after_commit("plan.updated", owner)
        end
      end

      result.entitlement = entitlement
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :entitlement

    def owner
      entitlement.catalog_plan || entitlement.plan
    end

    # Read on the column: a discarded catalog plan is hidden by its default scope.
    def catalog_plan?
      entitlement.catalog_plan_id.present?
    end

    def entitlement_events?
      entitlement.organization.feature_flag_enabled?(:entitlement_events)
    end

    # Re-read under the plan lock, so that the second of two concurrent deletes finds it discarded and answers
    # not found, with one event only. The reload drops what the caller preloaded for its render: load it again.
    def reload_under_lock!
      entitlement.reload
      result.not_found_failure!(resource: "feature").raise_if_error! if entitlement.discarded?

      ActiveRecord::Associations::Preloader.new(records: [entitlement], associations: [:catalog_plan, :feature, {values: :privilege}]).call
    end

    # Its values are discarded with it: the log and the webhook render the ones it had before.
    def send_deleted_events(values_before)
      if Utils::ActivityLog.available?
        Utils::ActivityLog.produce_after_commit(
          entitlement, "plan_entitlement.deleted",
          changes: {"values" => [values_before, nil]},
          activity_object: ::V2::PlanEntitlementSerializer.new(entitlement, values: values_before).serialize
        )
      end
      SendWebhookJob.perform_after_commit("plan_entitlement.deleted", entitlement, {values: values_before})
    end
  end
end
