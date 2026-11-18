# frozen_string_literal: true

module Entitlement
  module Concerns
    # Serializes the entitlement writes of one plan or subscription. Call a helper first, inside the transaction.
    # Lock order: the owner (plan or subscription) first, then its features ordered by id. Never lock an owner after a feature.
    module OwnerLockConcern
      extend ActiveSupport::Concern

      PLAN_UNIQUE_INDEXES = {
        "idx_unique_feature_per_plan" => :feature,
        "idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a" => :privilege
      }.freeze

      SUBSCRIPTION_UNIQUE_INDEXES = {
        "idx_unique_feature_per_subscription" => :feature,
        "idx_unique_feature_removal_per_subscription" => :feature,
        "idx_unique_privilege_removal_per_subscription" => :privilege,
        "idx_on_entitlement_privilege_id_entitlement_entitle_9d0542eb1a" => :privilege
      }.freeze

      private

      # FOR NO KEY UPDATE does not conflict with the key-share locks that the inserts of entitlements
      # and values take on the plan through their foreign keys. lock! reloads unscoped, hence the discarded? check.
      def lock_plan!(plan)
        result.not_found_failure!(resource: "plan").raise_if_error! if plan.nil?

        plan.lock!("FOR NO KEY UPDATE")
        result.not_found_failure!(resource: "plan").raise_if_error! if plan.discarded?
      end

      def lock_subscription!(subscription)
        subscription.lock!("FOR NO KEY UPDATE")
      end

      # A locked SELECT re-checks deleted_at on the version committed by the feature and privilege services, which
      # lock the feature FOR UPDATE. FOR SHARE locks do not block each other, so writes on other owners do not wait.
      # includes runs a separate query after the lock: a JOIN would lock the privileges too.
      def lock_features!(codes)
        features = organization.features.where(code: codes).order(:id).lock("FOR SHARE").includes(:privileges).to_a
        result.not_found_failure!(resource: "feature").raise_if_error! if features.size < codes.uniq.size

        features.index_by(&:code)
      end
    end
  end
end
