# frozen_string_literal: true

module Entitlement
  class PlanEntitlementsUpdateService < BaseService
    include ::Entitlement::Concerns::CreateOrUpdateConcern
    include ::Entitlement::Concerns::OwnerLockConcern

    Result = BaseResult[:entitlements, :failed_field]

    # Catalog plans only: legacy plans keep no limit.
    MAX_CATALOG_PLAN_ENTITLEMENTS = 200
    MAX_CATALOG_PLAN_ENTITLEMENT_VALUES = 50

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
    #       gets its own activity log and webhook, and without it nothing is sent.
    activity_loggable(
      action: "plan.updated",
      record: -> { plan },
      condition: -> { send_webhook && !catalog_plan? }
    )

    def call
      ActiveRecord::Base.transaction do
        lock_plan!(plan)
        baseline = catalog_plan_counts if catalog_plan?
        refuse_oversized_replace!(baseline) if catalog_plan? && !partial?
        stored_before = stored_values_by_entitlement_id if catalog_plan?
        rendered_before = rendered_values_by_entitlement_id if render_entitlement_changes?
        delete_missing_entitlements unless partial?
        update_entitlements
        check_catalog_plan_limits!(baseline) if catalog_plan?
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

    # The logs and the webhooks render every entitlement of the plan before and after the call, so they are only
    # built when one of them can be sent.
    def render_entitlement_changes?
      entitlement_events? && (Utils::ActivityLog.available? || send_entitlement_webhooks?)
    end

    # The jobs are enqueued in one bulk push, which skips the endpoint check of SendWebhookJob.perform_later.
    def send_entitlement_webhooks?
      return @send_entitlement_webhooks if defined?(@send_entitlement_webhooks)

      @send_entitlement_webhooks = organization.webhook_endpoints.exists?
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
      send_entitlement_events(changed_ids, rendered_before) if rendered_before
    end

    # One activity log and one webhook per changed entitlement, with the values before and after. Each log gets its
    # render from here, where the values are preloaded, so that it does not serialize the entitlement on its own after
    # the commit.
    def send_entitlement_events(changed_ids, values_before)
      entitlements = Entitlement.with_discarded.where(id: changed_ids)
        .includes(:catalog_plan, :feature, values: :privilege).newest_first

      webhook_jobs = entitlements.filter_map do |entitlement|
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

        if Utils::ActivityLog.available?
          Utils::ActivityLog.produce_after_commit(
            entitlement, "plan_entitlement.#{action}",
            changes: {"values" => [before, after]},
            # A dropped entitlement is logged with its deletion time and the values it had: they are discarded with it.
            activity_object: (action == "deleted") ? render.merge(values: before) : render
          )
        end
        next unless send_entitlement_webhooks?

        webhook_args = ["plan_entitlement.#{action}", entitlement]
        # The values of a dropped entitlement are discarded with it: its webhook gets the ones it had before.
        webhook_args << {values: before} if action == "deleted"
        SendWebhookJob.new(*webhook_args)
      end

      after_commit { ApplicationJob.perform_all_later(webhook_jobs) } if webhook_jobs.any?
    end

    # The kept entitlements of the plan and the kept values of each, by feature code, read in SQL.
    def catalog_plan_counts
      values = EntitlementValue
        .where(entitlement_entitlement_id: plan.entitlements.select(:id))
        .joins(entitlement: :feature)
        .group("#{Feature.table_name}.code")
        .count

      {entitlements: plan.entitlements.count, values:}
    end

    # A full replace leaves exactly the features of its body, so an oversized one is refused before
    # any write. A partial write and the values are checked on the state after the write.
    def refuse_oversized_replace!(baseline)
      count = entitlements_params.size
      return unless count > MAX_CATALOG_PLAN_ENTITLEMENTS && count > baseline[:entitlements]

      result.single_validation_failure!(
        field: :base, error_code: "too_many_entitlements", meta: {max_items: MAX_CATALOG_PLAN_ENTITLEMENTS}
      ).raise_if_error!
    end

    # Counts the state after the write. A count already over its limit before the write is refused
    # only when the write raises it, so that a plan over the limit can still be edited.
    def check_catalog_plan_limits!(baseline)
      after = catalog_plan_counts
      errors = {}
      meta = {}

      if after[:entitlements] > MAX_CATALOG_PLAN_ENTITLEMENTS && after[:entitlements] > baseline[:entitlements]
        errors[:base] = ["too_many_entitlements"]
        meta[:base] = {max_items: MAX_CATALOG_PLAN_ENTITLEMENTS}
      end

      # Only the features of the body can gain values.
      entitlements_params.each_key do |feature_code|
        count = after[:values].fetch(feature_code, 0)
        next unless count > MAX_CATALOG_PLAN_ENTITLEMENT_VALUES && count > baseline[:values].fetch(feature_code, 0)

        field = :"entitlements.#{feature_code}"
        errors[field] = ["too_many_values"]
        meta[field] = {max_items: MAX_CATALOG_PLAN_ENTITLEMENT_VALUES}
      end
      return if errors.empty?

      result.validation_failure!(errors:, meta:).raise_if_error!
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

    # The privilege values of a feature are a map of privilege codes to values. A legacy plan also reads a blank value
    # (null, "" or []) as no values, as it always did; a catalog plan refuses it.
    def validate_privilege_values_shape!(path, privilege_values)
      return if privilege_values.is_a?(Hash) || (privilege_values.blank? && !catalog_plan?)

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
