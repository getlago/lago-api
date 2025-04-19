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
      # Do progressive billing stuff

      Alert.where(
        subscription_external_id: subscription.external_id,
        organization_id: subscription_activity.organization_id,
        alert_type: Alert::CURRENT_USAGE_TYPES
      ).includes(:thresholds).find_each do |alert|
        ProcessAlertService.call(alert:, subscription:, thing_that_has_values_in_it: current_usage)
      end

      # Other Alert types go here... one day

      subscription_activity.delete

      result
    end

    private

    attr_reader :subscription_activity, :subscription

    def current_usage
      @current_usage ||= ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false, # Never use taxes for alerting
        with_cache: true
      ).usage
    end
  end
end
