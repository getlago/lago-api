# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern
    include ::Entitlement::Concerns::OwnerLockConcern
    include ::Entitlement::Concerns::EntryPathConcern

    Result = BaseResult[:entitlements, :failed_field]

    def initialize(organization:, plan:, entitlements_params:, partial:, send_webhook: true)
      @organization = organization
      @plan = plan
      @entitlements_params = entitlements_params.to_h.with_indifferent_access
      @partial = partial
      @send_webhook = send_webhook
      super
    end

    # NOTE: send_webhook gates the activity log too: both represent the same plan.updated event.
    #       It is set to false when invoked from the plan create/update mutations, where the plan
    #       service already emits the plan event, to avoid duplicates.
    #       A catalog plan gets no plan.updated event: with the entitlement_events flag, each entitlement it changes
    #       is logged on its own, and without it nothing is logged.
    activity_loggable(
      action: "plan.updated",
      record: -> { plan },
      condition: -> { send_webhook && !catalog_plan? }
    )

    def call
      ActiveRecord::Base.transaction do
        lock_plan!(plan)
        stored_before = stored_values_by_entitlement_id if catalog_plan?
        rendered_before = rendered_values_by_entitlement_id if log_entitlement_changes?
        delete_missing_entitlements unless partial?
        update_entitlements
        track_entitlement_changes(stored_before, rendered_before) if catalog_plan?
      end

      # NOTE: The webhook is sent even if no changes were made to the plan
      SendWebhookJob.perform_after_commit("plan.updated", plan) if send_webhook && !catalog_plan?

      # A legacy plan keeps its unordered relation, as before catalog plans existed.
      result.entitlements = if catalog_plan?
        plan.entitlements.includes(:catalog_plan, :feature, values: :privilege).newest_first.reload
      else
        plan.entitlements.includes(:feature, values: :privilege).reload
      end
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, plan_unique_indexes(plan))
    end

    private

    attr_reader :organization, :plan, :entitlements_params, :partial, :send_webhook
    alias_method :partial?, :partial

    def catalog_plan?
      plan.is_a?(CatalogPlan)
    end

    def owner_attributes
      catalog_plan? ? {catalog_plan: plan} : {plan:}
    end

    # The per-entitlement events of a catalog plan are behind the entitlement_events flag.
    def entitlement_events?
      catalog_plan? && organization.feature_flag_enabled?(:entitlement_events)
    end

    # The logs render every entitlement of the plan before and after the call, so they are only built
    # when they can be sent.
    def log_entitlement_changes?
      entitlement_events? && Utils::ActivityLog.available?
    end

    # The stored values of each kept entitlement of the plan, by privilege id, in two queries: enough to
    # find the entitlements a call changed, without rendering them.
    def stored_values_by_entitlement_id
      values = EntitlementValue.where(entitlement: plan.entitlements)
        .pluck(:entitlement_entitlement_id, :entitlement_privilege_id, :value)
        .group_by(&:first)
        .transform_values { |rows| rows.to_h { |_, privilege_id, value| [privilege_id, value] } }

      plan.entitlements.pluck(:id).index_with { values.fetch(it, {}) }
    end

    # The values of the kept entitlements of the plan, as their activity log renders them.
    def rendered_values_by_entitlement_id
      plan.entitlements.includes(:catalog_plan, :feature, values: :privilege).to_h do |entitlement|
        [entitlement.id, ::V2::PlanEntitlementSerializer.new(entitlement).serialize[:values]]
      end
    end

    # An entitlement added, discarded or whose stored values changed. Its values are its content, so a kept one is
    # touched to tell API and webhook clients through its updated_at; a discarded one got it from the discard.
    def track_entitlement_changes(stored_before, rendered_before)
      stored_after = stored_values_by_entitlement_id
      changed_ids = (stored_before.keys | stored_after.keys).reject { stored_before[it] == stored_after[it] }
      return if changed_ids.empty?

      Entitlement.where(id: changed_ids).touch_all # rubocop:disable Rails/SkipsModelValidations
      log_entitlement_changes(changed_ids, rendered_before) if rendered_before
    end

    # One activity log per changed entitlement, with the values before and after. Each log gets its render from
    # here, where the values are preloaded, so that it does not serialize the entitlement on its own after the commit.
    def log_entitlement_changes(changed_ids, values_before)
      entitlements = Entitlement.with_discarded.where(id: changed_ids)
        .includes(:catalog_plan, :feature, values: :privilege).newest_first

      entitlements.each do |entitlement|
        render = ::V2::PlanEntitlementSerializer.new(entitlement).serialize
        before = values_before[entitlement.id]
        after = entitlement.discarded? ? nil : render[:values]
        next if before == after
        action = if before.nil?
          "created"
        elsif after.nil?
          "deleted"
        else
          "updated"
        end

        Utils::ActivityLog.produce_after_commit(
          entitlement, "plan_entitlement.#{action}",
          changes: {"values" => [before, after]},
          # A dropped entitlement is logged with its deletion time and the values it had: they are discarded with it.
          activity_object: (action == "deleted") ? render.merge(values: before) : render
        )
      end
    end

    def delete_missing_entitlements
      missing = plan.entitlements.joins(:feature).where.not(feature: {code: entitlements_params.keys})
      EntitlementValue.where(entitlement: missing).discard_all!
      missing.discard_all!
    end

    def delete_missing_entitlement_values(entitlement, privilege_values)
      return if privilege_values.blank?

      entitlement.values.joins(:privilege).where.not(privilege: {code: privilege_values.keys}).discard_all!
    end

    def update_entitlements
      return if entitlements_params.blank?

      features_by_code = organization.features
        .where(code: entitlements_params.keys)
        .includes(:privileges)
        .index_by(&:code)

      entitlements_by_feature_id = plan.entitlements
        .where(entitlement_feature_id: features_by_code.values.map(&:id))
        .includes(:values)
        .index_by(&:entitlement_feature_id)

      entitlements_params.each do |feature_code, privilege_values|
        path = :"entitlements.#{feature_code}"
        feature = features_by_code[feature_code] || not_found_at!(path, "feature")
        validate_privilege_values_shape!(path, privilege_values)

        # Find existing entitlement or create new one
        entitlement = entitlements_by_feature_id[feature.id]

        if entitlement.nil?
          entitlement = Entitlement.create!(organization:, feature:, **owner_attributes)
        elsif !partial?
          delete_missing_entitlement_values(entitlement, privilege_values)
        end

        update_entitlement_values(entitlement, feature, privilege_values, path)
      end
    end

    def update_entitlement_values(entitlement, feature, privilege_values, feature_path)
      return if privilege_values.blank?

      privilege_values.each do |privilege_code, value|
        path = :"#{feature_path}.#{privilege_code}"
        privilege = feature.privileges.find { it.code == privilege_code } || not_found_at!(path, "privilege")
        value = validate_value(value, privilege, path:)
        entitlement_value = entitlement.values.find { it.entitlement_privilege_id == privilege.id }

        save_value_at!(path) do
          if entitlement_value
            entitlement_value.update!(value:)
          else
            EntitlementValue.create!(organization:, entitlement:, privilege:, value:)
          end
        end
      end
    end
  end
end
