# frozen_string_literal: true

module Entitlement
  # Merges an entitlements map into the overrides of a contract. A value equal to the catalog plan
  # value drops the override, as on v1 subscriptions.
  class ContractEntitlementUpdateService < BaseService
    include ::Entitlement::Concerns::OwnerLockConcern
    include ::Entitlement::Concerns::OverrideOwnerConcern
    include ::Entitlement::Concerns::EntryPathConcern

    Result = BaseResult[:entitlements, :failed_field]

    def initialize(contract:, entitlements_params:)
      @contract = contract
      @entitlements_params = entitlements_params.to_h.with_indifferent_access
      super
    end

    def call
      return result.not_found_failure!(resource: "contract") unless contract

      ActiveRecord::Base.transaction do
        lock_override_owner!(contract)
        # NOTE: Without entitlement_events, the write logs nothing.
        entitlements_before = SubscriptionEntitlement.for_contract(contract) if log_entitlement_changes?
        update_entitlements
        result.entitlements = SubscriptionEntitlement.for_contract(contract)
        log_entitlement_changes(entitlements_before, result.entitlements) if log_entitlement_changes?
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      # The core service names the failing privilege of an entry on its own result.
      result.failed_field ||= e.result.try(:failed_field)
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, CONTRACT_UNIQUE_INDEXES)
    end

    private

    attr_reader :contract, :entitlements_params
    delegate :organization, to: :contract

    def entitlement_events?
      organization.feature_flag_enabled?(:entitlement_events)
    end

    # The logs render the contract entitlements before the call, so they are only built when they can be sent.
    def log_entitlement_changes?
      entitlement_events? && Utils::ActivityLog.available?
    end

    def update_entitlements
      return if entitlements_params.blank?

      features_by_code = organization.features
        .where(code: entitlements_params.keys)
        .includes(:privileges)
        .index_by(&:code)
      feature_ids = features_by_code.values.map(&:id)

      plan_entitlements_by_feature_id = owner_plan_entitlements(contract)
        .where(entitlement_feature_id: feature_ids)
        .includes(values: :privilege)
        .index_by(&:entitlement_feature_id)

      contract_entitlements_by_feature_id = contract.entitlements
        .where(entitlement_feature_id: feature_ids)
        .includes(values: :privilege)
        .index_by(&:entitlement_feature_id)

      entitlements_params.each do |feature_code, privilege_params|
        path = :"entitlements.#{feature_code}"
        feature = features_by_code[feature_code] || not_found_at!(path, "feature")
        refuse_non_map!(path, privilege_params)

        SubscriptionEntitlementCoreUpdateService.call!(
          owner: contract,
          plan: contract.catalog_plan,
          feature:,
          privilege_params:,
          plan_entitlement: plan_entitlements_by_feature_id[feature.id],
          sub_entitlement: contract_entitlements_by_feature_id[feature.id],
          partial: true,
          path:
        )
      end
    end

    # A feature value is a map, empty for none. Any other value, blank ones included (null, "", false), is refused,
    # as on the catalog plan merge.
    def refuse_non_map!(path, privilege_params)
      return if privilege_params.is_a?(Hash)

      result.single_validation_failure!(field: path, error_code: "value_is_invalid").raise_if_error!
    end

    # One activity log per entitlement of the body whose values that apply changed (value, plan value or source),
    # filed under the contract, with the entitlement before and after. An entitlement left as it was gets none.
    def log_entitlement_changes(entitlements_before, entitlements_after)
      feature_codes = entitlements_params.keys
      before = entitlements_before.select { feature_codes.include?(it.code) }.index_by(&:code)
      after = entitlements_after.select { feature_codes.include?(it.code) }.index_by(&:code)
      changed_codes = (before.keys | after.keys).reject { rendered_values(before[it]) == rendered_values(after[it]) }

      # Newest first, in the order of the contract read.
      ordered_codes = after.keys.select { changed_codes.include?(it) } + (changed_codes - after.keys)
      ordered_codes.each do |code|
        action = if before[code].nil?
          "created"
        elsif after[code].nil?
          "deleted"
        else
          "updated"
        end

        Utils::ActivityLog.produce_after_commit(
          contract, "contract_entitlement.#{action}",
          activity_object: contract_entitlement_render(after[code] || before[code]),
          changes: {"values" => [rendered_values(before[code]), rendered_values(after[code])]}
        )
      end
    end

    def contract_entitlement_render(contract_entitlement)
      ::V2::ContractEntitlementSerializer.new(contract_entitlement).serialize
    end

    def rendered_values(contract_entitlement)
      contract_entitlement_render(contract_entitlement)[:values] if contract_entitlement
    end
  end
end
