# frozen_string_literal: true

module UsageMonitoring
  # Evaluates the current usage alerts that the triggered metric codes can move, once the usage buckets
  # reached the trigger watermark. reason says why nothing was evaluated (:no_alert, or why the wait gave up).
  class EvaluateRealtimeUsageAlertsService < BaseService
    Result = BaseResult[:reason]

    PER_METRIC_ALERT_TYPES = (Alert::CURRENT_USAGE_TYPES & Alert::BILLABLE_METRIC_TYPES).freeze

    def initialize(subscription:, codes:, watermark_ms:)
      @subscription = subscription
      @codes = codes
      @watermark_ms = watermark_ms
      super
    end

    def call
      alerts = alerts_moved_by_codes

      result.reason = if alerts.empty?
        :no_alert
      else
        RealtimeUsage.consistent_reads { evaluate(alerts) }
      end

      result
    end

    private

    attr_reader :subscription, :codes, :watermark_ms

    # Any event moves the plan total; a per-metric alert only moves with an event of its metric.
    def alerts_moved_by_codes
      alerts = Alert.where(organization_id: subscription.organization_id, subscription_external_id: subscription.external_id)

      alerts.where(alert_type: "current_usage_amount")
        .or(alerts.where(
          alert_type: PER_METRIC_ALERT_TYPES,
          billable_metric_id: BillableMetric.where(organization_id: subscription.organization_id, code: codes).select(:id)
        ))
        .order(:created_at, :id)
        .to_a
    end

    # Evaluating on buckets that have not caught up would stamp the alert with an older usage than
    # the one the event made, so a timeout leaves the subscription to the sweep.
    def evaluate(alerts)
      wait_reason = RealtimeUsage::WaitForBucketsService.call(
        organization_id: subscription.organization_id,
        pending: {subscription.id => watermark_ms},
        lane: :usage_alerts,
        log_context: {subscription_id: subscription.id}
      ).reason
      return wait_reason if wait_reason

      started_at = Time.current
      EvaluateSubscriptionUsageAlertsService.call!(subscription:, alerts:)
      Yabeda.usage_monitoring.usage_alerts_evaluation_duration.measure({}, Time.current - started_at)

      nil
    end
  end
end
