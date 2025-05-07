# frozen_string_literal: true

module UsageMonitoring
  class ProcessSubscriptionActivityService < BaseService
    Result = BaseResult

    def initialize(subscription_activity:)
      @subscription_activity = subscription_activity
      @subscription = subscription_activity.subscription
      super
    end

    def call
      lifetime_usage = find_or_create_lifetime_usage

      if organization.lifetime_usage_enabled? || organization.progressive_billing_enabled?
        LifetimeUsages::CalculateService.call!(lifetime_usage:, current_usage:)
      end

      if organization.progressive_billing_enabled?
        LifetimeUsages::CheckThresholdsService.call(lifetime_usage:)
      end

      Alert.where(
        subscription_external_id: subscription.external_id,
        organization_id: subscription_activity.organization_id,
        alert_type: Alert::CURRENT_USAGE_TYPES
      ).includes(:thresholds).find_each do |alert|
        ProcessAlertService.call(alert:, subscription:, current_metrics: current_usage)
      end

      subscription_activity.delete

      result
    end

    private

    delegate :organization, to: :subscription

    attr_reader :subscription_activity, :subscription

    def current_usage
      @current_usage ||= ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false, # Never use taxes for alerting
        with_cache: true
      ).usage
    end

    def find_or_create_lifetime_usage
      subscription.lifetime_usage || subscription.create_lifetime_usage!(organization:)
    end
  end
end
