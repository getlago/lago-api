# frozen_string_literal: true

# Consumes wallet_refresh_triggers (produced by the realtime usage pipeline,
# keyed by organization_id+customer_id) and refreshes wallets inline.
#
# Batch-collapse: N messages for one customer in a batch cost one refresh —
# only the latest usage state matters, so catch-up work is O(distinct
# customers), not O(messages). Refreshing inline (no job hop) preserves the
# per-partition ordering guarantee: one customer is never refreshed
# concurrently, so wallet rows see no lock contention.
class WalletRefreshTriggersConsumer < ApplicationConsumer
  def consume
    messages
      .map(&:payload)
      .compact # upsert-format retractions arrive as tombstones (nil payload)
      .group_by { |payload| [payload["organization_id"], payload["customer_id"]] }
      .each do |(organization_id, customer_id), payloads|
        wallet_codes = payloads.filter_map { |p| p["target_wallet_code"].presence }.uniq

        # Per-subscription watermarks: the refresh waits for projections to
        # reach the latest last_ingested_at seen in this batch (epoch millis).
        expected_ingested_at = payloads
          .group_by { |p| p["subscription_id"] }
          .transform_values { |rows| Time.at(rows.filter_map { |r| r["last_ingested_at"] }.max.to_f / 1000.0).utc }

        result = Wallets::RealtimeRefreshService.call(organization_id:, customer_id:, wallet_codes:, expected_ingested_at:)
        next if result.success?

        Rails.logger.error(
          "[wallets] realtime refresh failed customer_id=#{customer_id}: #{result.error}"
        )
        Sentry.capture_message("wallet realtime refresh failed", extra: {customer_id:, error: result.error.to_s})
      end
  end
end
