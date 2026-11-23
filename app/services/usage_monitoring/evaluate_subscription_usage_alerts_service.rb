# frozen_string_literal: true

module UsageMonitoring
  class EvaluateSubscriptionUsageAlertsService < BaseService
    Result = BaseResult

    # full_plan_usage must cover every charge of the plan: current_usage_amount alerts read its total.
    def initialize(subscription:, alerts:, lifetime_usage: nil, full_plan_usage: nil)
      @subscription = subscription
      @alerts = alerts
      @lifetime_usage = lifetime_usage
      @full_plan_usage = full_plan_usage
      super
    end

    def call
      check_alerts_belong_to_subscription!

      exception_to_raise = nil

      alerts.each do |alert|
        case alert.alert_type
        when "lifetime_usage_amount"
          ProcessAlertService.call(alert:, alertable: subscription, current_metrics: lifetime_usage)
        when *Alert::BILLABLE_METRIC_LIFETIME_USAGE_TYPES
          after_commit { ProcessLifetimeUsageAlertJob.set(wait: processing_interval).perform_later(alert:, subscription:) }
        when *Alert::CURRENT_USAGE_TYPES
          ProcessAlertService.call(alert:, alertable: subscription, current_metrics: current_usage)
        end
      rescue => e
        exception_to_raise ||= e
      end

      raise exception_to_raise if exception_to_raise

      result
    end

    private

    delegate :organization, to: :subscription

    attr_reader :subscription, :alerts, :full_plan_usage

    # Callers build the alert list themselves, so a wrong one would trigger alerts against this subscription.
    def check_alerts_belong_to_subscription!
      foreign_alert_ids = alerts.reject do |alert|
        alert.organization_id == subscription.organization_id && alert.subscription_external_id == subscription.external_id
      end.map(&:id)
      return if foreign_alert_ids.empty?

      raise ArgumentError, "alerts #{foreign_alert_ids.join(", ")} do not belong to subscription #{subscription.id}"
    end

    def processing_interval
      (ENV["LAGO_SUBSCRIPTION_ACTIVITY_PROCESSING_INTERVAL_SECONDS"].presence || 1.minute).to_i.seconds
    end

    def lifetime_usage
      @lifetime_usage ||= subscription.lifetime_usage || subscription.create_lifetime_usage!(organization:)
    end

    def current_usage
      @current_usage ||= full_plan_usage || ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false, # Never use taxes for alerting
        with_cache: true,
        use_usage_buckets: true
      ).usage
    end
  end
end
