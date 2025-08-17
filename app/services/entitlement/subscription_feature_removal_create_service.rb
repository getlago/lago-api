# frozen_string_literal: true

module Entitlement
  class SubscriptionFeatureRemovalCreateService < BaseService
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

      unless feature_available_in_plan?
        return result.validation_failure!(errors: {feature: ["feature_not_available_in_plan"]})
      end

      if feature_already_removed?
        return result.validation_failure!(errors: {feature: ["feature_already_removed"]})
      end

      subscription_feature_removal = nil
      ActiveRecord::Base.transaction do
        subscription_feature_removal = SubscriptionFeatureRemoval.create!(
          organization: subscription.organization,
          feature: feature,
          subscription_id: subscription.id
        )
      end

      SendWebhookJob.perform_after_commit("subscription.updated", subscription)

      result.subscription_feature_removal = subscription_feature_removal
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :subscription, :feature

    def feature_available_in_plan?
      Entitlement.joins(:feature)
        .where(plan_id: subscription.plan.parent_id || subscription.plan.id, feature: feature)
        .exists?
    end

    def feature_already_removed?
      SubscriptionFeatureRemoval
        .where(subscription_id: subscription.id, feature: feature)
        .first
    end
  end
end
