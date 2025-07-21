# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementDestroyService < BaseService
    Result = BaseResult[:entitlement]

    def initialize(subscription:, entitlement:)
      @subscription = subscription
      @entitlement = entitlement
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      ActiveRecord::Base.transaction do
        entitlement.values.discard_all!
        entitlement.discard!
      end

      SendWebhookJob.perform_after_commit("subscription.updated", subscription)

      result.entitlement = entitlement
      result
    end

    private

    attr_reader :subscription, :entitlement
  end
end
