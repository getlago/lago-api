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
      exception_to_raise = nil

      alerts.each do |alert|
        case alert.alert_type
        when "lifetime_usage_amount"
          ProcessAlertService.call(alert:, alertable: subscription, current_metrics: lifetime_usage)
        when *Alert::BILLABLE_METRIC_LIFETIME_USAGE_TYPES
          ProcessLifetimeUsageAlertJob.set(wait: processing_interval).perform_later(alert:, subscription:)
        when *Alert::CURRENT_USAGE_TYPES
          ProcessAlertService.call(alert:, alertable: subscription, current_metrics: current_usage)
        end
      rescue => e
        exception_to_raise ||= e
      end

      trace_usage_path

      raise exception_to_raise if exception_to_raise

      result
    end

    private

    delegate :organization, to: :subscription

    attr_reader :subscription, :alerts, :full_plan_usage

    def processing_interval
      (ENV["LAGO_SUBSCRIPTION_ACTIVITY_PROCESSING_INTERVAL_SECONDS"].presence || 1.minute).to_i.seconds
    end

    def lifetime_usage
      @lifetime_usage ||= subscription.lifetime_usage || subscription.create_lifetime_usage!(organization:)
    end

    def current_usage
      @current_usage ||= if full_plan_usage
        @usage_path = "full_plan_reused"
        full_plan_usage
      else
        @usage_path = "full_plan_failed"
        compute_full_plan_usage.tap { @usage_path = "full_plan" if it }
      end
    end

    def compute_full_plan_usage
      ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false, # Never use taxes for alerting
        with_cache: true,
        use_usage_buckets: true
      ).usage
    end

    def trace_usage_path
      OpenTelemetry::Trace.current_span.add_attributes(
        "usage_monitoring.alerts_count" => alerts.size,
        "usage_monitoring.usage_path" => @usage_path || "none"
      )
    end
  end
end
