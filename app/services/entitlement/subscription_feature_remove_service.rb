# frozen_string_literal: true

module Entitlement
  # Removes a feature from a subscription or a contract (the override owner).
  class SubscriptionFeatureRemoveService < BaseService
    include Concerns::OwnerLockConcern
    include Concerns::OverrideOwnerConcern

    Result = BaseResult[:feature_code]

    def initialize(owner:, feature_code:)
      @owner = owner
      @feature_code = feature_code
      super
    end

    # The subscription event only: the callers of a contract log their own.
    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless owner
      return result.not_found_failure!(resource: "feature") unless feature

      ActiveRecord::Base.transaction do
        lock_override_owner!(owner)
        delete_subscription_entitlement_if_exists
        delete_privilege_removals_if_exists
        add_feature_removal_if_feature_is_in_plan
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
