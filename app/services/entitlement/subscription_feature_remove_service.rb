# frozen_string_literal: true

module Entitlement
  # Removes a feature from a subscription or a contract (the override owner).
  class SubscriptionFeatureRemoveService < BaseService
    include Concerns::OwnerLockConcern
    include Concerns::OverrideOwnerConcern
    include Concerns::ContractEntitlementEventsConcern

    # entitlement: for a contract, the feature as it applied to the contract before the removal.
    Result = BaseResult[:feature_code, :entitlement]

    def initialize(owner:, feature_code:)
      @owner = owner
      @feature_code = feature_code
      super
    end

    # The subscription event only: a contract logs contract_entitlement.deleted.
    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription },
      condition: -> { subscription.present? }
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless owner
      # A contract checks its status first, so a contract that cannot be edited refuses any feature code.
      return result.not_found_failure!(resource: "feature") unless contract || feature

      ActiveRecord::Base.transaction do
        lock_override_owner!(owner)
        if contract
          lock_feature!
          find_contract_entitlement!
        end
        delete_subscription_entitlement_if_exists
        delete_privilege_removals_if_exists
        add_feature_removal_if_feature_is_in_plan
        send_contract_entitlement_deleted_events if contract
      end

      SendWebhookJob.perform_after_commit("subscription.updated", subscription) if subscription

      result.feature_code = feature_code
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :owner, :feature_code
    delegate :organization, to: :owner

    def subscription
      owner if owner.is_a?(Subscription)
    end

    def contract
      owner if owner.is_a?(Contract)
    end

    # FOR KEY SHARE waits for a feature delete in progress, which discards the contract removals of the feature, so
    # no removal is stored for a deleted feature. lock! reloads unscoped, hence the discarded? check.
    def lock_feature!
      feature&.lock!("FOR KEY SHARE")
      result.not_found_failure!(resource: "feature").raise_if_error! if feature.nil? || feature.discarded?
    end

    # Read under the contract lock, so that of two concurrent removals the second one finds nothing.
    # A feature that does not apply to the contract (never granted or already removed) is not found.
    def find_contract_entitlement!
      result.entitlement = SubscriptionEntitlement.for_contract(contract).find { it.entitlement_feature_id == feature.id }
      result.not_found_failure!(resource: "feature").raise_if_error! unless result.entitlement
    end

    def send_contract_entitlement_deleted_events
      return unless render_contract_entitlement_events?(contract)

      send_contract_entitlement_events(contract, [[render_contract_entitlement(result.entitlement), nil]])
    end

    def feature
      @feature ||= organization.features.find_by(code: feature_code)
    end

    def delete_subscription_entitlement_if_exists
      entitlement = owner.entitlements.find_by(feature:)
      return unless entitlement
      entitlement.values.update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
      entitlement.discard!
    end

    def delete_privilege_removals_if_exists
      owner.entitlement_removals.where(privilege: feature.privileges).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
    end

    def add_feature_removal_if_feature_is_in_plan
      return unless owner_plan_entitlements(owner).where(entitlement_feature_id: feature.id).exists?

      owner_key = override_owner_key(owner)
      SubscriptionFeatureRemoval.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: organization.id, "#{owner_key}_id": owner.id, entitlement_feature_id: feature.id}],
        unique_by: :"idx_unique_feature_removal_per_#{owner_key}"
      )
    end
  end
end
