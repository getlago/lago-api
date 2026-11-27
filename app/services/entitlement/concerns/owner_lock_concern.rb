# frozen_string_literal: true

module Entitlement
  module Concerns
    # Serializes the entitlement writes of one plan or subscription. Call a helper first, inside the transaction.
    module OwnerLockConcern
      extend ActiveSupport::Concern

      PLAN_UNIQUE_INDEXES = {
        "idx_unique_feature_per_plan" => :feature,
        "idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a" => :privilege
      }.freeze

      CATALOG_PLAN_UNIQUE_INDEXES = {
        "idx_unique_feature_per_catalog_plan" => :feature,
        "idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a" => :privilege
      }.freeze

      SUBSCRIPTION_UNIQUE_INDEXES = {
        "idx_unique_feature_per_subscription" => :feature,
        "idx_unique_feature_removal_per_subscription" => :feature,
        "idx_unique_privilege_removal_per_subscription" => :privilege,
        "idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a" => :privilege
      }.freeze

      private

      # Locks a plan or a catalog plan. FOR NO KEY UPDATE does not conflict with the key-share locks that the inserts
      # of entitlements and values take on the plan through their foreign keys. lock! reloads unscoped, hence the discarded? check.
      def lock_plan!(plan)
        result.not_found_failure!(resource: "plan").raise_if_error! if plan.nil?

        plan.lock!("FOR NO KEY UPDATE")
        result.not_found_failure!(resource: "plan").raise_if_error! if plan.discarded?
      end

      def plan_unique_indexes(plan)
        plan.is_a?(CatalogPlan) ? CATALOG_PLAN_UNIQUE_INDEXES : PLAN_UNIQUE_INDEXES
      end

      def lock_subscription!(subscription)
        subscription.lock!("FOR NO KEY UPDATE")
      end
    end
  end
end
