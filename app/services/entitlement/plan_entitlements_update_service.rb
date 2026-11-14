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
    #       A catalog plan gets the plan.updated activity log and a plan.entitlements_updated webhook instead of plan.updated.
    activity_loggable(
      action: "plan.updated",
      record: -> { plan },
      condition: -> { send_webhook }
    )

    def call
      ActiveRecord::Base.transaction do
        lock_plan!(plan)
        delete_missing_entitlements unless partial?
        update_entitlements
      end

      # NOTE: The webhook is sent even if no changes were made to the plan
      if send_webhook
        webhook_type = plan.is_a?(CatalogPlan) ? "plan.entitlements_updated" : "plan.updated"
        SendWebhookJob.perform_after_commit(webhook_type, plan)
      end

      result.entitlements = plan.entitlements.includes(:feature, values: :privilege).oldest_first.reload
      result
    rescue BaseService::ValidationFailure => e
      record_failing_entry
      result.fail_with_error!(at_entry_path(e, :"#{@current_privilege_code}_privilege_value"))
    rescue BaseService::FailedResult => e
      record_failing_entry
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, plan_unique_indexes(plan))
    rescue ActiveRecord::RecordInvalid => e
      record_failing_entry
      if e.record.is_a?(EntitlementValue)
        result.fail_with_error!(entitlement_value_failure(e.record))
      else
        result.record_validation_failure!(record: e.record)
      end
    rescue ActiveRecord::RecordNotFound => e
      record_failing_entry
      if e.message.include?("Entitlement::Feature")
        result.not_found_failure!(resource: "feature")
      elsif e.message.include?("Entitlement::Privilege")
        result.not_found_failure!(resource: "privilege")
      else
        result.not_found_failure!(resource: "record")
      end
    end

    private

    attr_reader :organization, :plan, :entitlements_params, :partial, :send_webhook
    alias_method :partial?, :partial

    # NOTE: The failures keep the keys that v1 and GraphQL clients read. The path of the failing entry
    #       lets the v2 controller point an unknown feature or privilege at entitlements.<feature>[.<privilege>].
    def record_failing_entry
      result.failed_field = entitlement_entry_field(@current_feature_code, @current_privilege_code) if @current_feature_code
    end

    # The path of an entry in the entitlements map of a request, which native v2 renders as the field.
    def entitlement_entry_field(feature_code, privilege_code = nil)
      privilege_code.nil? ? :"entitlements.#{feature_code}" : :"entitlements.#{feature_code}.#{privilege_code}"
    end

    # The failure with the codes and meta of v1_field on the path of the failing entry, which native v2
    # renders. Its messages keep the keys that v1 and GraphQL clients read.
    def at_entry_path(failure, v1_field)
      entry_path = entitlement_entry_field(@current_feature_code, @current_privilege_code)
      v2_field = ->(field) { (field.to_sym == v1_field) ? entry_path : field }

      BaseService::ValidationFailure.new(
        result,
        messages: failure.messages,
        codes: failure.codes.transform_keys(&v2_field),
        meta: failure.meta.transform_keys(&v2_field)
      )
    end

    # v1 and GraphQL clients read privilege.<attribute>.
    def entitlement_value_failure(entitlement_value)
      failure = BaseService::ValidationFailure.from_errors(result, entitlement_value.errors).remap(result) { :"privilege.#{it}" }

      at_entry_path(failure, :"privilege.value")
    end

    def owner_attributes
      plan.is_a?(CatalogPlan) ? {catalog_plan: plan} : {plan:}
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
        @current_feature_code = feature_code
        @current_privilege_code = nil
        feature = features_by_code[feature_code]

        raise ActiveRecord::RecordNotFound.new("Entitlement::Feature") unless feature

        # Find existing entitlement or create new one
        entitlement = entitlements_by_feature_id[feature.id]

        if entitlement.nil?
          entitlement = Entitlement.create!(organization:, feature:, **owner_attributes)
        elsif !partial?
          delete_missing_entitlement_values(entitlement, privilege_values)
        end

        update_entitlement_values(entitlement, feature, privilege_values)
      end
    end

    def create_entitlement_values(entitlement, feature, privilege_values)
      privilege_values.each do |privilege_code, value|
        @current_privilege_code = privilege_code
        privilege = feature.privileges.find { it.code == privilege_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Privilege") unless privilege

        create_entitlement_value(entitlement, privilege, value)
      end
    end

    def update_entitlement_values(entitlement, feature, privilege_values)
      return if privilege_values.blank?

      privilege_values.each do |privilege_code, value|
        @current_privilege_code = privilege_code
        privilege = feature.privileges.find { it.code == privilege_code }

        raise ActiveRecord::RecordNotFound.new("Entitlement::Privilege") unless privilege

        entitlement_value = entitlement.values.find { it.entitlement_privilege_id == privilege.id }

        if entitlement_value
          entitlement_value.update!(value: validate_value(value, privilege))
        else
          create_entitlement_value(entitlement, privilege, value)
        end
      end
    end

    def create_entitlement_value(entitlement, privilege, value)
      EntitlementValue.create!(
        organization: organization,
        entitlement: entitlement,
        privilege: privilege,
        value: validate_value(value, privilege)
      )
    end
  end
end
