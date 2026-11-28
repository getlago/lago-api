# frozen_string_literal: true

module Entitlement
  # Merges an entitlements map into the overrides of a contract. A value equal to the catalog plan
  # value drops the override, as on v1 subscriptions.
  class ContractEntitlementUpdateService < BaseService
    include ::Entitlement::Concerns::OwnerLockConcern
    include ::Entitlement::Concerns::OverrideOwnerConcern
    include ::Entitlement::Concerns::EntryPathConcern
    include ::Entitlement::Concerns::ContractEntitlementEventsConcern

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
        # NOTE: Without entitlement_events, the write logs and sends nothing.
        events = entitlements_params.present? && render_contract_entitlement_events?(contract)
        if events
          # A catalog plan write committed between the two reads would be sent as a change of this call.
          contract.catalog_plan&.lock!("FOR SHARE")
          entitlements_before = SubscriptionEntitlement.for_contract(contract)
        end
        update_entitlements
        result.entitlements = SubscriptionEntitlement.for_contract(contract)
        send_entitlement_events(entitlements_before, result.entitlements) if events
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

    # One activity log and one webhook per entitlement of the body whose values that apply changed (value, plan value
    # or source). An entitlement left as it was gets none. A feature granted back after its removal is created.
    def send_entitlement_events(entitlements_before, entitlements_after)
      feature_codes = entitlements_params.keys
      before = render_by_code(entitlements_before.select { feature_codes.include?(it.code) })
      after = render_by_code(entitlements_after.select { feature_codes.include?(it.code) })
      changed_codes = (before.keys | after.keys).reject { before[it]&.dig(:values) == after[it]&.dig(:values) }

      # Newest first, in the order of the contract read.
      ordered_codes = after.keys.select { changed_codes.include?(it) } + (changed_codes - after.keys)
      send_contract_entitlement_events(contract, ordered_codes.map { [before[it], after[it]] })
    end

    def render_by_code(contract_entitlements)
      contract_entitlements.to_h { [it.code, render_contract_entitlement(it)] }
    end
  end
end
