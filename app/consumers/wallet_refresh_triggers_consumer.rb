# frozen_string_literal: true

# Refreshing inline rather than through a job keeps the partition's ordering: the topic is keyed
# by (organization_id, customer_id), so the consumer never refreshes one customer twice at once.
class WalletRefreshTriggersConsumer < ApplicationConsumer
  # A batch outliving max.poll.interval.ms gets the member evicted and the batch replayed by its
  # next owner, forever. What the deadline cuts stays flagged for the sweep.
  CONSUME_DEADLINE = 2.minutes

  def consume
    payloads = messages.map(&:payload).compact # upsert-format retractions arrive as tombstones
    report_messages(payloads.size)

    organization_ids = realtime_organization_ids(payloads)
    deadline = Time.current + CONSUME_DEADLINE

    customer_batches = payloads.group_by { |payload| [payload["organization_id"], payload["customer_id"]] }

    customer_batches.each_with_index do |((organization_id, customer_id), customer_payloads), index|
      if deadline_reached?(deadline)
        report(:skipped, :deadline, by: customer_batches.size - index)
        break
      end

      unless organization_ids.include?(organization_id)
        report(:skipped, :not_realtime)
        next
      end

      # The trigger sink emits for every metered customer, and most hold no wallet.
      unless Wallet.active.exists?(organization_id:, customer_id:)
        report(:skipped, :no_wallet)
        next
      end

      refresh(organization_id, customer_id, customer_payloads)
    end
  end

  private

  def refresh(organization_id, customer_id, customer_payloads)
    wallet_codes = customer_payloads.filter_map { |p| p["target_wallet_code"].presence }.uniq

    # Kept as integer epoch millis end-to-end: converting through Time.at(float) can land a
    # microsecond above the stored timestamp and never match.
    expected_ingested_at = customer_payloads
      .select { |p| p["subscription_id"].present? }
      .group_by { |p| p["subscription_id"] }
      .transform_values { |rows| rows.filter_map { |r| r["last_ingested_at"] }.max }
      .compact

    result = Wallets::RealtimeRefreshService.call(organization_id:, customer_id:, wallet_codes:, expected_ingested_at:)

    unless result.success?
      report(:failed, :refresh_failed)
      Rails.logger.error(
        "[wallets] realtime refresh failed customer_id=#{customer_id}: #{result.error}"
      )
      Sentry.capture_message("wallet realtime refresh failed", extra: {customer_id:, error: result.error.to_s})
      return
    end

    if result.reason
      report(:skipped, result.reason)
      return
    end

    report(:refreshed, :none)
    report_latency(expected_ingested_at)
  rescue => e
    # Raising out of #consume pauses the partition and replays the batch, re-refreshing every
    # customer already done. StaleObjectError against the sweep is the expected one.
    report(:failed, :refresh_raised)
    Rails.logger.error(
      "[wallets] realtime refresh raised customer_id=#{customer_id}: #{e.class} #{e.message}"
    )
    Sentry.capture_exception(e, extra: {customer_id:})
  end

  def deadline_reached?(deadline)
    return false if Time.current <= deadline

    Rails.logger.warn("[wallets] realtime refresh batch hit its deadline, remaining customers left to the sweep")
    true
  end

  # Off the realtime path no read path uses the buckets, so the refresh would wait out its grace
  # for nothing and the sweep already covers those customers.
  def realtime_organization_ids(payloads)
    Organization
      .where(id: payloads.filter_map { it["organization_id"] }.uniq)
      .select { RealtimeUsage.enabled?(it) && !RealtimeUsage.deduplicated?(it) }
      .map(&:id)
      .to_set
  end

  def report(outcome, reason, by: 1)
    Yabeda.realtime_usage.wallet_refresh_outcomes_total.increment(
      {outcome: outcome.to_s, reason: reason.to_s}, by:
    )
  end

  def report_messages(trigger_count)
    counter = Yabeda.realtime_usage.wallet_refresh_messages_total
    counter.increment({kind: "trigger"}, by: trigger_count)
    counter.increment({kind: "tombstone"}, by: messages.size - trigger_count)
  end

  def report_latency(expected_ingested_at)
    watermark_ms = expected_ingested_at.values.max
    return if watermark_ms.nil?

    latency = Time.current.to_f - (watermark_ms.to_i / 1000.0)
    Yabeda.realtime_usage.wallet_refresh_latency.measure({}, latency)
  end
end
