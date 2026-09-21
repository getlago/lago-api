# frozen_string_literal: true

# Refreshing inline rather than through a job preserves the partition's ordering: the topic is
# keyed by (organization_id, customer_id), so one customer is never refreshed concurrently.
class WalletRefreshTriggersConsumer < ApplicationConsumer
  def consume
    payloads = messages.map(&:payload).compact # upsert-format retractions arrive as tombstones
    organization_ids = realtime_organization_ids(payloads)

    payloads
      .group_by { |payload| [payload["organization_id"], payload["customer_id"]] }
      .each do |(organization_id, customer_id), customer_payloads|
        next unless organization_ids.include?(organization_id)

        # The trigger sink emits for every metered customer, and most hold no wallet.
        next unless Wallet.active.exists?(organization_id:, customer_id:)

        wallet_codes = customer_payloads.filter_map { |p| p["target_wallet_code"].presence }.uniq

        # Kept as integer epoch millis end-to-end: converting through Time.at(float) can land a
        # microsecond above the stored timestamp and never match.
        expected_ingested_at = customer_payloads
          .group_by { |p| p["subscription_id"] }
          .transform_values { |rows| rows.filter_map { |r| r["last_ingested_at"] }.max }
          .compact

        result = Wallets::RealtimeRefreshService.call(organization_id:, customer_id:, wallet_codes:, expected_ingested_at:)
        next if result.success?

        Rails.logger.error(
          "[wallets] realtime refresh failed customer_id=#{customer_id}: #{result.error}"
        )
        Sentry.capture_message("wallet realtime refresh failed", extra: {customer_id:, error: result.error.to_s})
      end
  end

  private

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
