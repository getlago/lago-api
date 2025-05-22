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
      exception_to_raise = nil
      lifetime_usage = find_or_create_lifetime_usage

      # NOTE: We would typically have one jobs for progressive billing and one job for Alerting
      #       but in order to reduce calls to `current_usage`, we do both in the same job.
      #       A simple rescue is added so ensure we process alert even if progressive billing breaks
      #       The subscription_activity is deleted if something raise.
      #       We believe it's a good tradeoff because they should rarely raise but this can change in the future

      begin
        if organization.using_lifetime_usage?
          LifetimeUsages::CalculateService.call!(lifetime_usage:, current_usage:)
        end

        if organization.progressive_billing_enabled?
          LifetimeUsages::CheckThresholdsService.call(lifetime_usage:)
        end
      rescue => e
        exception_to_raise = e
      end

      begin
        alerts = Alert.where(
          subscription_external_id: subscription.external_id,
          organization_id: subscription_activity.organization_id
        ).includes(:thresholds)

        alerts.using_current_usage.find_each do |alert|
          ProcessAlertService.call(alert:, subscription:, current_metrics: current_usage)
        end

        alerts.using_lifetime_usage.find_each do |alert|
          ProcessAlertService.call(alert:, subscription:, current_metrics: lifetime_usage)
        end
      rescue => e
        # If progressive billing already raised, we don't override the first error
        exception_to_raise = e if exception_to_raise.nil?
      end

      subscription_activity.delete

      if exception_to_raise
        raise exception_to_raise
      end

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
