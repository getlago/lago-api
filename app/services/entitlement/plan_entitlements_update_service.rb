# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern
    include ::Entitlement::Concerns::OwnerLockConcern

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

      result.entitlements = plan.entitlements.includes(:catalog_plan, :feature, values: :privilege).newest_first.reload
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

    # NOTE: The failures keep the keys that v1 and GraphQL clients read, and put their codes on the path of
    #       the failing entry of the request (entitlements.<feature>[.<privilege>]), which native v2 renders.
    #       failed_field lets the v2 controller render an unknown feature or privilege on that path.
    def not_found_at!(path, resource)
      result.failed_field = path
      result.not_found_failure!(resource:).raise_if_error!
    end

    # v1 and GraphQL clients read privilege.<attribute>.
    def save_value_at!(path)
      yield
    rescue ActiveRecord::RecordInvalid => e
      raise unless e.record.is_a?(EntitlementValue)

      failure = BaseService::ValidationFailure.from_errors(result, e.record.errors)
      at_path = ->(field) { (field.to_sym == :value) ? path : :"privilege.#{field}" }
      raise BaseService::ValidationFailure.new(
        result,
        messages: failure.messages.transform_keys { :"privilege.#{it}" },
        codes: failure.codes.transform_keys(&at_path),
        meta: failure.meta.transform_keys(&at_path)
      )
    end

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
    def rendered_values_by_entitlement_id(ids = nil)
      entitlements = plan.entitlements.includes(:catalog_plan, :feature, values: :privilege)
      entitlements = entitlements.where(id: ids) if ids

      entitlements.to_h do |entitlement|
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

    # One activity log per changed entitlement, with the values before and after.
    def log_entitlement_changes(changed_ids, values_before)
      values_after = rendered_values_by_entitlement_id(changed_ids)

      Entitlement.with_discarded.where(id: changed_ids).includes(:catalog_plan, :feature).newest_first.each do |entitlement|
        before = values_before[entitlement.id]
        after = values_after[entitlement.id]
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
          activity_object: (action == "deleted") ? deleted_entitlement_render(entitlement, before) : nil
        )
      end
    end

    # A dropped entitlement as it was before the call, with its deletion time: its values are discarded with it.
    def deleted_entitlement_render(entitlement, values_before)
      ::V2::PlanEntitlementSerializer.new(entitlement).serialize.merge(values: values_before)
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
        validate_privilege_values_shape!(path, privilege_values)
        feature = features_by_code[feature_code] || not_found_at!(path, "feature")

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

    # The privilege values of a feature are a map of privilege codes to values, or empty for none.
    def validate_privilege_values_shape!(path, privilege_values)
      return if privilege_values.blank? || privilege_values.is_a?(Hash)

      result.single_validation_failure!(field: path, error_code: "value_is_invalid").raise_if_error!
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
