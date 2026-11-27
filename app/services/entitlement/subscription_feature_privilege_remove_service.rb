# frozen_string_literal: true

module Entitlement
  # Removes a privilege value from a subscription or a contract (the override owner).
  class SubscriptionFeaturePrivilegeRemoveService < BaseService
    include Concerns::OwnerLockConcern
    include Concerns::OverrideOwnerConcern
    include Concerns::ContractEntitlementEventsConcern
    include Concerns::ContractRemovalsConcern

    # entitlement: for a contract, the feature as it applies to the contract after the removal.
    Result = BaseResult[:feature_code, :privilege_code, :entitlement]

    def initialize(owner:, feature_code:, privilege_code:)
      @owner = owner
      @feature_code = feature_code
      @privilege_code = privilege_code
      super
    end

    # The subscription event only: a contract logs contract_entitlement.updated.
    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription },
      condition: -> { subscription.present? }
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless owner
      # A contract checks its status first, so a contract that cannot be edited refuses any feature or privilege code.
      unless contract
        return result.not_found_failure!(resource: "feature") unless feature
        return result.not_found_failure!(resource: "privilege") unless privilege
      end

      ActiveRecord::Base.transaction do
        lock_override_owner!(owner)
        if contract
          lock_feature_for_contract_removal!(feature)
          # A privilege delete holds the feature lock, so the privilege read before it may be discarded since.
          result.not_found_failure!(resource: "privilege").raise_if_error! if privilege.nil? || privilege.reload.discarded?
        end
        before_render = find_contract_entitlement_before! if contract
        delete_subscription_entitlement_value_if_exists
        add_privilege_removal_if_privilege_is_in_plan
        send_contract_entitlement_updated_events(before_render) if contract
      end

      SendWebhookJob.perform_after_commit("subscription.updated", subscription) if subscription

      result.feature_code = feature_code
      result.privilege_code = privilege_code
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :owner, :feature_code, :privilege_code
    delegate :organization, to: :owner

    def subscription
      owner if owner.is_a?(Subscription)
    end

    def contract
      owner if owner.is_a?(Contract)
    end

    def feature
      @feature ||= organization.features.find_by(code: feature_code)
    end

    def privilege
      @privilege ||= organization.privileges.find_by(code: privilege_code, feature:)
    end

    def contract_entitlement
      SubscriptionEntitlement.for_contract_feature(contract, feature)
    end

    # Read under the contract lock, so that of two concurrent removals the second one finds nothing. A feature that
    # does not apply to the contract, or a value that it does not have (never set or already removed), is not found.
    # Returns the render before the removal when an event can be sent.
    def find_contract_entitlement_before!
      before = contract_entitlement
      result.not_found_failure!(resource: "feature").raise_if_error! unless before
      result.not_found_failure!(resource: "privilege").raise_if_error! if before.privileges.none? { it.code == privilege_code }

      render_contract_entitlement(before) if render_contract_entitlement_events?(contract)
    end

    # The plan still grants the feature, or the contract-only row is kept, so the feature still applies, unless a plan
    # entitlement or feature delete, which does not lock the contract, committed in between.
    def send_contract_entitlement_updated_events(before_render)
      result.entitlement = contract_entitlement
      result.not_found_failure!(resource: "feature").raise_if_error! unless result.entitlement

      if before_render
        send_contract_entitlement_events(contract, [[before_render, render_contract_entitlement(result.entitlement)]])
      end
    end

    def delete_subscription_entitlement_value_if_exists
      entitlement = owner.entitlements.find_by(feature: feature)
      return unless entitlement
      entitlement.values.where(privilege:).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations

      if contract && owner_plan_entitlements(owner).where(feature:).exists?
        discard_empty_contract_entitlement(owner, entitlement)
      end
    end

    # A subscription stores a removal when its plan grants the feature, a contract only when its plan sets the value.
    def add_privilege_removal_if_privilege_is_in_plan
      plan_entitlements = owner_plan_entitlements(owner).where(feature:)
      in_plan = if contract
        EntitlementValue.where(entitlement: plan_entitlements, privilege:).exists?
      else
        plan_entitlements.exists?
      end
      return unless in_plan

      owner_key = override_owner_key(owner)
      SubscriptionFeatureRemoval.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: organization.id, "#{owner_key}_id": owner.id, entitlement_privilege_id: privilege.id}],
        unique_by: :"idx_unique_privilege_removal_per_#{owner_key}"
      )
    end
  end
end
