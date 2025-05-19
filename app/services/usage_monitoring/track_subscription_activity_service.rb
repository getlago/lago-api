# frozen_string_literal: true

module UsageMonitoring
  class TrackSubscriptionActivityService < BaseService
    Result = BaseResult

    # NOTE: The organization can be passed to avoid loading it from the subscription
    #       If not passed, it's lazy loaded from the subscription
    def initialize(subscription:, organization: nil)
      @subscription = subscription
      @organization = organization
      super
    end

    def call
      return result unless License.premium?
      return result unless subscription.active?
      return result unless need_lifetime_usage? || has_alerts?

      UsageMonitoring::SubscriptionActivity.insert_all( # rubocop:disable Rails/SkipsModelValidations
        [{organization_id: organization.id, subscription_id: subscription.id}],
        unique_by: :idx_subscription_unique
      )

      result
    end

    private

    attr_reader :subscription

    def organization
      @organization ||= subscription.organization
    end

    def need_lifetime_usage?
      return true if organization.lifetime_usage_enabled?

      organization.progressive_billing_enabled? && subscription.usage_thresholds.any?
    end

    def has_alerts?
      Alert.where(subscription_external_id: subscription.external_id).any?
    end
  end
end
