# frozen_string_literal: true

module Entitlement
  class SubscriptionFeatureRemovalDestroyService < BaseService
    Result = BaseResult[:subscription_feature_removal]

    def initialize(subscription:, feature:)
      @subscription = subscription
      @feature = feature
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.not_found_failure!(resource: "feature") unless feature

      subscription_feature_removal = find_removal
      return result.not_found_failure!(resource: "subscription_feature_removal") unless subscription_feature_removal

      subscription_feature_removal.discard!

      SendWebhookJob.perform_after_commit("subscription.updated", subscription)

      result.subscription_feature_removal = subscription_feature_removal
      result
    end

    private

    attr_reader :subscription, :feature

    def find_removal
      SubscriptionFeatureRemoval
        .where(subscription_id: subscription.id, feature: feature)
        .where(deleted_at: nil)
        .first
    end
  end
end
