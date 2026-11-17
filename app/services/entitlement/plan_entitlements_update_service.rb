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
    #       A catalog plan gets no plan.updated event: each entitlement it changes is logged on its own.
    activity_loggable(
      action: "plan.updated",
      record: -> { plan },
      condition: -> { send_webhook && !catalog_plan? }
    )

    def call
      ActiveRecord::Base.transaction do
        lock_plan!(plan)
        values_before = rendered_values_by_entitlement_id if catalog_plan?
        delete_missing_entitlements unless partial?
        update_entitlements
        log_entitlement_changes(values_before) if catalog_plan?
      end

      # NOTE: The webhook is sent even if no changes were made to the plan
      SendWebhookJob.perform_after_commit("plan.updated", plan) if send_webhook && !catalog_plan?

      result.entitlements = plan.entitlements.includes(:feature, values: :privilege).oldest_first.reload
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

    # The values of each kept entitlement of the plan, as its activity log renders them.
    def rendered_values_by_entitlement_id
      plan.entitlements.includes(:catalog_plan, :feature, values: :privilege).to_h do |entitlement|
        [entitlement.id, ::V2::PlanEntitlementSerializer.new(entitlement).serialize[:values]]
      end
    end

    # One activity log per entitlement the call added, changed (any of its values) or discarded,
    # with the values before and after. An entitlement left as it was gets none.
    def log_entitlement_changes(values_before)
      values_after = rendered_values_by_entitlement_id
      changed_ids = (values_before.keys | values_after.keys).reject { values_before[it] == values_after[it] }

      Entitlement.with_discarded.where(id: changed_ids).oldest_first.each do |entitlement|
        before = values_before[entitlement.id]
        after = values_after[entitlement.id]
        action = if before.nil?
          "created"
        elsif after.nil?
          "deleted"
        else
          "updated"
        end

        Utils::ActivityLog.produce_after_commit(entitlement, "plan_entitlement.#{action}", changes: {"values" => [before, after]})
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
