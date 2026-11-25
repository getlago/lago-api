# frozen_string_literal: true

# Evaluates current usage alerts seconds after their buckets land, instead of at the next clock tick. The sweep
# still runs on the same alerts, so the lane relies on ProcessAlertService skipping a usage measured before the
# alert's last evaluation. The topic is keyed by (organization_id, customer_id), so the consumer never evaluates
# one subscription twice at once.
class SubscriptionUsageAlertsConsumer < ApplicationConsumer
  # A batch outliving max.poll.interval.ms gets the member evicted and the batch replayed by its
  # next owner, forever. What the deadline cuts stays with the sweep.
  CONSUME_DEADLINE = 2.minutes

  def consume
    payloads = messages.map(&:payload).compact # upsert-format retractions arrive as tombstones
    return if payloads.empty?

    organization_ids = enabled_organization_ids(payloads)
    deadline = Time.current + CONSUME_DEADLINE

    subscription_batches, disabled_batches = payloads
      .group_by { [it["organization_id"], it["subscription_id"]] }
      .partition { |(organization_id, _), _| organization_ids.include?(organization_id) }
    report(:skipped, :not_enabled, by: disabled_batches.size) if disabled_batches.any?

    subscription_batches.each_with_index do |((organization_id, subscription_id), subscription_payloads), index|
      if Time.current > deadline
        report(:skipped, :deadline, by: subscription_batches.size - index)
        Rails.logger.warn("[alerts] usage alerts batch hit its deadline, remaining subscriptions left to the sweep")
        break
      end

      process(organization_id, subscription_id, subscription_payloads)
    end
  end

  private

  def process(organization_id, subscription_id, subscription_payloads)
    subscription = Subscription.active.find_by(id: subscription_id, organization_id:) if subscription_id.present?
    return report(:skipped, :subscription_not_found) if subscription.nil?

    # Kept as integer epoch millis end-to-end: converting through Time.at(float) can land a
    # microsecond above the stored timestamp and never match.
    watermark_ms = subscription_payloads.filter_map { it["last_ingested_at"] }.max
    return report(:skipped, :no_watermark) if watermark_ms.nil?

    reason = UsageMonitoring::EvaluateRealtimeUsageAlertsService.call!(
      subscription:,
      codes: subscription_payloads.filter_map { it["code"] }.uniq,
      watermark_ms:
    ).reason
    return report(:skipped, reason) if reason

    report(:evaluated, :none)
    Yabeda.usage_monitoring.usage_alerts_latency.measure({}, Time.current.to_f - (watermark_ms.to_i / 1000.0))
  rescue => e
    # Broad on purpose: an error raised out of #consume pauses the partition and replays the batch, so one
    # programming error would hold every later trigger. Sentry gets each error, and the sweep keeps the subscription.
    report(:failed, :evaluation_raised)
    Rails.logger.error(
      "[alerts] usage alerts evaluation raised subscription_id=#{subscription_id}: #{e.class} #{e.message}"
    )
    Sentry.capture_exception(e, extra: {subscription_id:})
  end

  def enabled_organization_ids(payloads)
    Organization
      .where(id: payloads.filter_map { it["organization_id"] }.uniq)
      .select { RealtimeUsage.alerts_enabled?(it) }
      .map(&:id)
      .to_set
  end

  def report(outcome, reason, by: 1)
    Yabeda.usage_monitoring.usage_alerts_outcomes_total.increment({outcome: outcome.to_s, reason: reason.to_s}, by:)
  end
end
