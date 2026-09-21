# frozen_string_literal: true

# Refreshing inline rather than through a job preserves the partition's ordering: the topic is
# keyed by (organization_id, customer_id), so one customer is never refreshed concurrently.
class WalletRefreshTriggersConsumer < ApplicationConsumer
  # Karafka holds the listener until #consume returns, so a batch that outlives
  # max.poll.interval.ms (5 minutes by default) gets the member evicted, its offsets dropped and
  # the whole batch replayed by the next owner — a loop that never drains. The customers left
  # over stay flagged and the sweep picks them up.
  CONSUME_DEADLINE = 2.minutes

  def consume
    payloads = messages.map(&:payload).compact # upsert-format retractions arrive as tombstones
    organization_ids = realtime_organization_ids(payloads)
    deadline = Time.current + CONSUME_DEADLINE

    payloads
      .group_by { |payload| [payload["organization_id"], payload["customer_id"]] }
      .each do |(organization_id, customer_id), customer_payloads|
        break if deadline_reached?(deadline)
        next unless organization_ids.include?(organization_id)

        # The trigger sink emits for every metered customer, and most hold no wallet.
        next unless Wallet.active.exists?(organization_id:, customer_id:)

        refresh(organization_id, customer_id, customer_payloads)
      end
  end

  private

  def refresh(organization_id, customer_id, customer_payloads)
    wallet_codes = customer_payloads.filter_map { |p| p["target_wallet_code"].presence }.uniq

    # Kept as integer epoch millis end-to-end: converting through Time.at(float) can land a
    # microsecond above the stored timestamp and never match.
    expected_ingested_at = customer_payloads
      .group_by { |p| p["subscription_id"] }
      .transform_values { |rows| rows.filter_map { |r| r["last_ingested_at"] }.max }
      .compact

    result = Wallets::RealtimeRefreshService.call(organization_id:, customer_id:, wallet_codes:, expected_ingested_at:)
    return if result.success?

    Rails.logger.error(
      "[wallets] realtime refresh failed customer_id=#{customer_id}: #{result.error}"
    )
    Sentry.capture_message("wallet realtime refresh failed", extra: {customer_id:, error: result.error.to_s})
  rescue => e
    # Letting this out of #consume pauses the partition and replays the batch, re-refreshing every
    # customer already done. StaleObjectError against the sweep is the expected occurrence.
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

  # The pipeline emits for every organization, but the buckets are only served for the ones
  # realtime usage is on for: elsewhere the refresh would wait out its grace on buckets no read
  # path would use anyway, and the sweep already covers those customers.
  def realtime_organization_ids(payloads)
    Organization
      .where(id: payloads.filter_map { it["organization_id"] }.uniq)
      .select { RealtimeUsage.enabled?(it) && !RealtimeUsage.deduplicated?(it) }
      .map(&:id)
      .to_set
  end
end
