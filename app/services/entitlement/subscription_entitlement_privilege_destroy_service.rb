# frozen_string_literal: true

module Entitlement
  class SubscriptionEntitlementPrivilegeDestroyService < BaseService
    Result = BaseResult[:entitlement_value]

    def initialize(subscription:, entitlement:, privilege_code:)
      @subscription = subscription
      @entitlement = entitlement
      @privilege_code = privilege_code
      super
    end

    activity_loggable(
      action: "subscription.updated",
      record: -> { subscription }
    )

    def call
      return result.forbidden_failure! unless License.premium?
      return result.not_found_failure!(resource: "entitlement") unless entitlement

      entitlement_value = entitlement.values.joins(:privilege).find_by(privilege: {code: privilege_code})
      return result.not_found_failure!(resource: "privilege") unless entitlement_value

      entitlement_value.discard!

      SendWebhookJob.perform_after_commit("subscription.updated", subscription)

      result.entitlement_value = entitlement_value
      result
    end

    private

    attr_reader :subscription, :entitlement, :privilege_code
  end
end
