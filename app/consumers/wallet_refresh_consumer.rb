# frozen_string_literal: true

# Refreshes the wallet ongoing balance as soon as the usage behind it is queryable. The
# pipeline emits one trigger per enriched count/sum event, keyed by
# (organization_id, customer_id).
#
# The trigger topic is shared by every realtime usage reaction, so each reaction gets its own
# consumer group: this one pauses its partition on the bucket watermark, and a group per
# reaction keeps that wait from stalling the others.
#
# Every trigger is acted on. The refresh carries the customer's wallet ids, which is how
# `Customers::RefreshWalletJob` runs for a customer the five-minute sweep has not flagged, so
# this lane owns the refreshes it dispatches instead of riding on the sweep's bookkeeping. A
# trigger whose buckets never land is given up on only after `MAX_WATERMARK_ATTEMPTS`, and
# then it goes to the dead letter queue rather than being dropped.
class WalletRefreshConsumer < ApplicationConsumer
  # Milliseconds. Pausing re-delivers the offset without holding a worker thread, where a
  # sleep would hold the thread and the partition for as long as it ran.
  WATERMARK_PAUSE_TIMEOUT = 1_000

  # Pause cycles one offset may spend waiting for its buckets, so five minutes at the timeout
  # above. Buckets that never land — the subscription carries no bucket-backed charge, or the
  # sink filtered the event — must neither stall the partition nor vanish unnoticed, so past
  # this budget the trigger goes to the dead letter queue.
  MAX_WATERMARK_ATTEMPTS = 300

  # A failed read cannot tell a late bucket from one that will never land, so ClickHouse being
  # unavailable holds the offset without spending its budget: that is backpressure, not a bad
  # message. Letting the error out would send the batch to the dead letter queue instead.
  CLICKHOUSE_ERRORS = [
    ActiveRecord::ActiveRecordError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    SocketError,
    SystemCallError
  ].freeze

  def consume
    @batch = messages.to_a
    @triggers = build_triggers

    return if triggers.empty?

    @refreshable_customers = fetch_refreshable_customers
    @active_wallet_ids = fetch_active_wallet_ids
    @caught_up_subscription_ids = fetch_caught_up_subscription_ids

    blocked_offsets = []

    triggers.each_value do |trigger|
      customer = refreshable_customers[trigger[:customer_id]]
      next if customer.nil?

      if buckets_caught_up?(trigger)
        Customers::RefreshWalletJob.perform_later(customer, wallet_ids: active_wallet_ids[customer.id])
      else
        blocked_offsets << trigger[:offset]
      end
    end

    wait_for_buckets(blocked_offsets.sort) if blocked_offsets.any?
  end

  private

  # Karafka keeps the consumer instance alive across batches (`consumer_persistence`), so the
  # per-batch state is rebuilt on every `consume` instead of being memoized.
  attr_reader :batch, :triggers, :refreshable_customers, :active_wallet_ids, :caught_up_subscription_ids

  # One entry per customer: N triggers for one customer cost one refresh, so catching up
  # costs O(distinct customers) rather than O(messages). An entry keeps the batch's highest
  # watermark together with the subscription that carried it — the event behind that
  # watermark landed in a bucket of that subscription, so that is where it will appear — and
  # the offset of the customer's first message, which is where the partition has to resume
  # when the customer turns out to be blocked.
  def build_triggers
    batch.each_with_object({}) do |message, acc|
      trigger = build_trigger(message)
      next if trigger.nil?

      known = acc[trigger[:customer_id]]

      if known.nil?
        acc[trigger[:customer_id]] = trigger
      elsif trigger[:watermark_ms] > known[:watermark_ms]
        known.merge!(trigger.slice(:watermark_ms, :subscription_id))
      end
    end
  end

  def build_trigger(message)
    payload = message.payload
    organization_id = payload["organization_id"]
    customer_id = payload["customer_id"]
    subscription_id = payload["subscription_id"]
    watermark_ms = epoch_ms(payload["last_ingested_at"])

    return nil if organization_id.blank? || customer_id.blank? || subscription_id.blank?

    # The sink does not COALESCE `ingested_at` and the topic contract does not guarantee it.
    # There is no epoch to wait for, and refreshing anyway would read the buckets early.
    if watermark_ms.nil?
      Karafka.logger.warn("#{self.class}: trigger without a watermark at offset #{message.offset}, skipped")

      return nil
    end

    {organization_id:, customer_id:, subscription_id:, watermark_ms:, offset: message.offset}
  end

  # The sink encodes `ingested_at` as integer epoch milliseconds (RisingWave's JSON rendering
  # of a naive timestamp), which is already the unit the watermark is compared in. The string
  # forms are tolerated so that quoting the number, or sinking the column as a timestamptz,
  # does not silently turn every trigger into a wait that can only time out.
  def epoch_ms(value)
    case value
    when Integer then value
    when String then value.match?(/\A\d+\z/) ? value.to_i : parsed_epoch_ms(value)
    end
  end

  # Converted through a Rational rather than a Float so the millisecond never rounds above
  # the one ClickHouse stored.
  def parsed_epoch_ms(value)
    time = Time.find_zone!("UTC").parse(value)

    (time.to_time.to_r * 1000).to_i if time
  end

  # One query for the whole batch. These filters decide whether a refresh could do anything at
  # all: without an active wallet there is no ongoing balance to refresh, a tax error makes
  # `Customers::RefreshWalletJob` return, and an organization outside the realtime usage
  # rollout has no buckets for its refresh to read.
  def fetch_refreshable_customers
    Customer
      .with_active_wallets
      .without_tax_errors
      .includes(:organization)
      .where(organization_id: triggers.each_value.map { it[:organization_id] }.uniq, id: triggers.keys)
      .distinct
      .index_by(&:id)
      .select { |_id, customer| RealtimeUsage.enabled?(customer.organization) }
  end

  # One query for the whole batch. The wallet ids are what let the job run for a customer the
  # sweep has not flagged, so this lane no longer depends on the sweep's bookkeeping to reach
  # the wallet.
  def fetch_active_wallet_ids
    Wallet
      .active
      .where(customer_id: refreshable_customers.keys)
      .pluck(:customer_id, :id)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last) }
  end

  def buckets_caught_up?(trigger)
    return false if watermark_read_failed?

    caught_up_subscription_ids.include?(trigger[:subscription_id])
  end

  def watermark_read_failed?
    caught_up_subscription_ids.nil?
  end

  # Only the customers a refresh could act on are worth a watermark: waiting on the others
  # would pause the partition for a refresh that is never dispatched.
  def fetch_caught_up_subscription_ids
    watermarks = triggers
      .each_value
      .select { refreshable_customers.key?(it[:customer_id]) }
      .map { it.slice(:organization_id, :subscription_id, :watermark_ms) }

    return Set.new if watermarks.empty?

    RealtimeUsage::BucketWatermarkService.call!(watermarks:).caught_up_subscription_ids
  rescue *CLICKHOUSE_ERRORS => e
    Karafka.logger.warn("#{self.class}: bucket watermark read failed (#{e.class}), waiting")

    nil
  end

  # Resuming re-delivers from the blocked offset, so nothing before it may stay uncommitted
  # and nothing at or after it may be committed. Karafka skips its own automatic marking once
  # the partition is manually paused.
  #
  # The attempt count lives on the consumer because Karafka resets its own pause tracker after
  # every successful `consume`. It only bounds the wait where the instance outlives the batch,
  # which is everywhere but development.
  def wait_for_buckets(offsets)
    offset = offsets.first

    if offset != @paused_offset
      @paused_offset = offset
      @paused_attempts = 0
    end

    @paused_attempts += 1 unless watermark_read_failed?

    if @paused_attempts > MAX_WATERMARK_ATTEMPTS
      give_up_on(offsets)
    else
      pause_on(offset)
    end
  end

  def pause_on(offset)
    index = batch.index { |message| message.offset == offset }

    mark_as_consumed(batch[index - 1]) if index.positive?

    pause(offset, WATERMARK_PAUSE_TIMEOUT)
  end

  # No other lane refreshes these customers, so a trigger whose buckets never landed is handed
  # to the dead letter queue instead of being dropped, and the partition moves on to the next
  # customer still waiting.
  #
  # `dispatch_to_dlq` is Karafka's own, from the route's dead letter queue: it builds the same
  # envelope and emits the same `dead_letter_queue.dispatched` event as an unprocessable
  # message, so both kinds of unprocessed trigger are replayed and monitored the same way.
  def give_up_on(offsets)
    message = batch.find { |candidate| candidate.offset == offsets.first }

    Karafka.logger.warn(
      "#{self.class}: buckets still behind at offset #{message.offset} after " \
      "#{@paused_attempts} attempts, moving the trigger to the dead letter queue"
    )

    dispatch_to_dlq(message)
    mark_as_consumed(message)

    remaining = offsets.drop(1)

    if remaining.any?
      @paused_offset = remaining.first
      @paused_attempts = 1

      pause(remaining.first, WATERMARK_PAUSE_TIMEOUT)
    else
      @paused_offset = nil
    end
  end
end
