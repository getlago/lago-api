# frozen_string_literal: true

module UsageMonitoring
  class EvaluateSubscriptionUsageAlertsService < BaseService
    Result = BaseResult

    # full_plan_usage is a UsageSnapshot covering every charge of the plan: current_usage_amount alerts read its total.
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
      current_usage = nil

      if current_usage_alerts.any?
        begin
          current_usage = full_plan_usage || UsageSnapshot.measure { compute_current_usage }
        rescue => e
          exception_to_raise = e
        end
      end

      alerts.each do |alert|
        case alert.alert_type
        when "lifetime_usage_amount"
          ProcessAlertService.call(alert:, alertable: subscription, current_metrics: lifetime_usage)
        when *Alert::BILLABLE_METRIC_LIFETIME_USAGE_TYPES
          after_commit { ProcessLifetimeUsageAlertJob.set(wait: processing_interval).perform_later(alert:, subscription:) }
        when *Alert::CURRENT_USAGE_TYPES
          # NOTE: a usage that failed to build would fail the same way for every alert
          next unless current_usage

          ProcessAlertService.call(
            alert:,
            alertable: subscription,
            current_metrics: current_usage.usage,
            measured_at: current_usage.measured_at,
            expected_billable_metric_id: (alert.billable_metric_id if scoped_to_metrics)
          )
        end
      rescue => e
        exception_to_raise ||= e
      end

      raise exception_to_raise if exception_to_raise

      result
    end

    private

    delegate :organization, to: :subscription

    attr_reader :subscription, :alerts, :full_plan_usage, :scoped_to_metrics

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

    def current_usage_alerts
      @current_usage_alerts ||= alerts.select { Alert::CURRENT_USAGE_TYPES.include?(it.alert_type) }
    end

    # current_usage_amount alerts read the plan total; the per-metric ones only read the fees of their metric.
    def compute_current_usage
      if current_usage_alerts.any? { it.alert_type == "current_usage_amount" }
        customer_usage.raise_if_error!.usage
      else
        metric_usage
      end
    end

    # A full plan usage holds every metric, so only a usage scoped to the alerts' metrics goes stale when one changes.
    def metric_usage
      @scoped_to_metrics = true
      billable_metric_ids = current_usage_alerts.map(&:billable_metric_id).uniq
      charge_ids = subscription.plan.charges.where(billable_metric_id: billable_metric_ids).ids
      return empty_usage if charge_ids.empty?

      usage_result = customer_usage(usage_filters: UsageFilters.new(filter_by_charge_id: charge_ids))

      # NOTE: the charges were removed from the plan since their ids were read
      if usage_result.error.is_a?(BaseService::NotFoundFailure) && usage_result.error.resource == "charge"
        empty_usage
      else
        usage_result.raise_if_error!.usage
      end
    end

    # No fees, so the per-metric alerts find no value and are not evaluated, as for a metric not on the plan.
    def empty_usage
      SubscriptionUsage.new(fees: [])
    end

    def customer_usage(**filters)
      ::Invoices::CustomerUsageService.call(
        customer: subscription.customer,
        subscription:,
        apply_taxes: false, # Never use taxes for alerting
        with_cache: true,
        use_usage_buckets: true,
        **filters
      )
    end
  end
end
