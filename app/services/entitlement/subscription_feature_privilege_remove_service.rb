# frozen_string_literal: true

module Entitlement
  # Removes a privilege value from a subscription or a contract (the override owner).
  class SubscriptionFeaturePrivilegeRemoveService < BaseService
    include Concerns::OwnerLockConcern
    include Concerns::OverrideOwnerConcern

    Result = BaseResult[:feature_code, :privilege_code]

    def initialize(owner:, feature_code:, privilege_code:)
      @owner = owner
      @feature_code = feature_code
      @privilege_code = privilege_code
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.not_found_failure!(resource: "subscription") unless owner
      return result.not_found_failure!(resource: "feature") unless feature
      return result.not_found_failure!(resource: "privilege") unless privilege

      ActiveRecord::Base.transaction do
        lock_override_owner!(owner)
        delete_subscription_entitlement_value_if_exists
        add_privilege_removal_if_privilege_is_in_plan
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

    def feature
      @feature ||= organization.features.find_by(code: feature_code)
    end

    def privilege
      @privilege ||= organization.privileges.find_by(code: privilege_code, feature:)
    end

    def delete_subscription_entitlement_value_if_exists
      entitlement = owner.entitlements.find_by(feature: feature)
      return unless entitlement
      entitlement.values.where(privilege:).update_all(discarded_columns) # rubocop:disable Rails/SkipsModelValidations
    end

    def add_privilege_removal_if_privilege_is_in_plan
      return unless owner_plan_entitlements(owner).where(feature:).exists?

      owner_key = override_owner_key(owner)
      SubscriptionFeatureRemoval.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: organization.id, "#{owner_key}_id": owner.id, entitlement_privilege_id: privilege.id}],
        unique_by: :"idx_unique_privilege_removal_per_#{owner_key}"
      )
    end
  end
end
