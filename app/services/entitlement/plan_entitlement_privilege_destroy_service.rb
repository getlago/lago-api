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

    # A catalog plan gets no plan.updated event: with the entitlement_events flag, it gets a plan_entitlement.updated
    # activity log and webhook, and without it nothing is sent.
    activity_loggable(
      action: "plan.updated",
      record: -> { entitlement && owner },
      condition: -> { entitlement && !catalog_plan? }
    )

    def call
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      entitlement_value = find_entitlement_value
      return result.not_found_failure!(resource: "privilege") unless entitlement_value

      if catalog_plan?
        destroy_catalog_plan_value
      else
        destroy_plan_value(entitlement_value)
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :entitlement, :privilege_code

    def owner
      entitlement.owner_plan
    end

    # Read on the column: a discarded catalog plan is hidden by its default scope.
    def catalog_plan?
      entitlement.catalog_plan_id.present?
    end

    # The value and the entitlement are read again under the lock: a concurrent removal answers not found privilege.
    # lock! reloads the catalog plan, which clears the query cache, so the reads below hit the database.
    def destroy_catalog_plan_value
      ActiveRecord::Base.transaction do
        lock_plan!(owner)

        locked_value = find_entitlement_value
        entitlement_before = locked_entitlement
        result.not_found_failure!(resource: "privilege").raise_if_error! unless locked_value && entitlement_before

        values_before = rendered_values(entitlement_before) if entitlement_events?
        locked_value.discard!
        # Its values are its content: its updated_at tells API and webhook clients they changed.
        Entitlement.where(id: entitlement.id).touch_all # rubocop:disable Rails/SkipsModelValidations

        result.entitlement = locked_entitlement
        send_updated_events(values_before) if entitlement_events?
      end
    end

    def entitlement_events?
      entitlement.organization.feature_flag_enabled?(:entitlement_events)
    end

    # The log gets its render from here, where the values are preloaded, so that it does not serialize the
    # entitlement on its own after the commit.
    def send_updated_events(values_before)
      if Utils::ActivityLog.available?
        render = ::V2::PlanEntitlementSerializer.new(result.entitlement).serialize
        Utils::ActivityLog.produce_after_commit(
          result.entitlement, "plan_entitlement.updated",
          changes: {"values" => [values_before, render[:values]]},
          activity_object: render
        )
      end
      SendWebhookJob.perform_after_commit("plan_entitlement.updated", result.entitlement)
    end

    # The kept entitlement with what its serializers read, loaded again on each call.
    def locked_entitlement
      Entitlement.includes(:catalog_plan, :feature, values: :privilege).find_by(id: entitlement.id)
    end

    def rendered_values(entitlement)
      ::V2::PlanEntitlementSerializer.new(entitlement).serialize[:values]
    end

    def destroy_plan_value(entitlement_value)
      ActiveRecord::Base.transaction do
        lock_plan!(entitlement.plan)

        # The value was loaded before the lock: a concurrent delete may have discarded it since.
        result.not_found_failure!(resource: "privilege").raise_if_error! if entitlement_value.reload.discarded?

        entitlement_value.discard!
      end

      SendWebhookJob.perform_after_commit("plan.updated", owner)

      # NOTE: reload the entitlement with all the associations required to serialize it
      result.entitlement = Entitlement.includes(:feature, values: :privilege).find_by(id: entitlement.id)
    end

    def find_entitlement_value
      entitlement.values.joins(:privilege).find_by(privilege: {code: privilege_code})
    end
  end
end
