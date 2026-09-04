# frozen_string_literal: true

# Refreshes the wallet ongoing balance as soon as the usage behind it is queryable. The
# pipeline emits one trigger per enriched count/sum event, keyed by
# (organization_id, customer_id).
#
# The trigger topic is shared by every realtime usage reaction, so each reaction gets its own
# consumer group: this one pauses its partition on the bucket watermark, and a group per
# reaction keeps that wait from stalling the others.
#
# The refresh carries the customer's wallet ids, which is how `Customers::RefreshWalletJob`
# runs for a customer the five-minute sweep has not flagged, so this lane does not ride on the
# sweep's bookkeeping to reach the wallet. A trigger whose buckets never land is given up on
# only after `MAX_WATERMARK_ATTEMPTS`, and then it goes to the dead letter queue rather than
# being dropped.
class WalletRefreshConsumer < ApplicationConsumer
  # Milliseconds. Pausing re-delivers the offset without holding a worker thread, where a
  # sleep would hold the thread and the partition for as long as it ran.
  WATERMARK_PAUSE_TIMEOUT = 1_000

  # Past this age the sweep is the cheaper lane, so the trigger is left to it: a backlog from
  # a restart or a downtime drains at full speed instead of being paused and waited through,
  # one offset at a time, for usage the sweep will pick up in one pass.
  MAX_TRIGGER_AGE = 30.seconds

  # Pause cycles one offset may spend waiting for its buckets, so five minutes at the timeout
  # above. Buckets that never land — the subscription carries no bucket-backed charge, or the
  # sink filtered the event — must neither stall the partition nor vanish unnoticed, so past
  # this budget the trigger goes to the dead letter queue.
  MAX_WATERMARK_ATTEMPTS = 300

  # Pause cycles a failed watermark read may spend before it stops being read as a blip. The
  # ClickHouse adapter reports an unreachable server and a query that can no longer run as the
  # same error, so past this the offset spends its attempt budget like any other wait and ends
  # up in the dead letter queue, rather than holding the partition for good.
  MAX_WATERMARK_READ_FAILURES = 30

  # Epoch milliseconds, whole or decimal, as opposed to a rendered timestamp.
  NUMERIC_EPOCH = /\A\d+(?:\.\d+)?\z/

  # Caught rather than let out: the error would fail a batch of thousands, of which Karafka
  # dead-letters only the first message. A read that fails is treated as backpressure instead,
  # bounded by `MAX_WATERMARK_READ_FAILURES`.
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

    log_stale_triggers

    blocked_offsets = triggers.empty? ? [] : dispatch_refreshes

    if blocked_offsets.any?
      wait_for_buckets(blocked_offsets.sort)
    else
      clear_pause_state
    end
  end

  private

  # Karafka keeps the consumer instance alive across batches (`consumer_persistence`), so the
  # per-batch state is rebuilt on every `consume` instead of being memoized.
  attr_reader :batch, :triggers, :stale_triggers, :refreshable_customers, :active_wallet_ids,
    :caught_up_subscription_ids

  # Returns the offset each blocked customer has to be resumed from.
  def dispatch_refreshes
    @refreshable_customers = fetch_refreshable_customers
    @active_wallet_ids = fetch_active_wallet_ids
    @caught_up_subscription_ids = fetch_caught_up_subscription_ids

    blocked_offsets = []

    triggers.each_value do |trigger|
      customer = refreshable_customers[trigger[:customer_id]]
      next if customer.nil?

      if buckets_caught_up?(trigger)
        refresh(customer, trigger) unless already_refreshed?(trigger)
      else
        blocked_offsets << trigger[:offset]
      end
    end

    blocked_offsets
  end

  def refresh(customer, trigger)
    Customers::RefreshWalletJob.perform_later(customer, wallet_ids: active_wallet_ids[customer.id])

    refreshed_watermarks_ms[trigger[:customer_id]] = trigger[:watermarks_ms]
  end

  # A pause re-delivers the whole batch, so one blocked subscription would otherwise cost the
  # batch's every other customer a refresh per cycle — up to `MAX_WATERMARK_ATTEMPTS` of them,
  # and `unique :until_executed` only collapses the ones still queued. A customer is refreshed
  # again once one of its subscriptions carries a watermark past the one already refreshed,
  # which is what usage ingested since looks like.
  #
  # Only offsets at or after the paused one come back, so the record is dropped as soon as the
  # partition resumes.
  def already_refreshed?(trigger)
    refreshed = refreshed_watermarks_ms[trigger[:customer_id]]

    return false if refreshed.nil?

    trigger[:watermarks_ms].all? { |subscription_id, watermark_ms| watermark_ms <= refreshed[subscription_id].to_i }
  end

  def refreshed_watermarks_ms
    @refreshed_watermarks_ms ||= {}
  end

  # Nothing is blocked, so the partition moves on and everything the wait carried across its
  # cycles goes with it.
  def clear_pause_state
    @paused_offset = nil
    @read_failures = 0
    @refreshed_watermarks_ms = nil
  end

  # One entry per customer: N triggers for one customer cost one refresh, so catching up
  # costs O(distinct customers) rather than O(messages). An entry keeps the batch's highest
  # watermark for every subscription it carried for that customer — the refresh recomputes
  # usage across all of the customer's active subscriptions, so waiting on one of them would
  # still debit the wallet against another's previous epoch — and the offset of the customer's
  # first message, which is where the partition has to resume when the customer turns out to
  # be blocked.
  def build_triggers
    @stale_triggers = 0

    batch.each_with_object({}) do |message, acc|
      trigger = build_trigger(message)
      next if trigger.nil?

      known = acc[trigger[:customer_id]]

      if known.nil?
        acc[trigger[:customer_id]] = trigger
      else
        known[:watermarks_ms].merge!(trigger[:watermarks_ms]) { |_id, kept, added| [kept, added].max }
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

    if stale?(message)
      @stale_triggers += 1

      return nil
    end

    # The sink does not COALESCE `ingested_at` and the topic contract does not guarantee it.
    # There is no epoch to wait for, and refreshing anyway would read the buckets early.
    if watermark_ms.nil?
      Karafka.logger.warn("#{self.class}: trigger without a watermark at offset #{message.offset}, skipped")

      return nil
    end

    {organization_id:, customer_id:, watermarks_ms: {subscription_id => watermark_ms}, offset: message.offset}
  end

  # Age is judged on first delivery only. A paused partition re-delivers the same messages
  # with their original timestamps, so judging them again would age out the very trigger the
  # pause is waiting for and drop it silently, short of the attempt budget and of the dead
  # letter queue.
  def stale?(message)
    return false if @paused_offset && message.offset >= @paused_offset

    message.timestamp < MAX_TRIGGER_AGE.ago
  end

  # Dropping a backlog is the policy, but it has to be visible: a pipeline lagging past the
  # window, or a producer clock sitting behind ours, otherwise looks exactly like silence.
  def log_stale_triggers
    return if stale_triggers.zero?

    Karafka.logger.warn(
      "#{self.class}: #{stale_triggers} trigger(s) older than #{MAX_TRIGGER_AGE.inspect}, left to the sweep"
    )
  end

  # The sink encodes `ingested_at` as integer epoch milliseconds (RisingWave's JSON rendering
  # of a naive timestamp), which is already the unit the watermark is compared in. The other
  # forms are tolerated so that quoting the number, rendering it as a decimal, or sinking the
  # column as a timestamptz, does not silently turn every trigger into a wait that can only
  # time out. Truncating rather than rounding keeps the expectation from landing above the
  # millisecond ClickHouse stored, which no bucket could ever satisfy.
  def epoch_ms(value)
    case value
    when Numeric then value.to_i
    when String then value.match?(NUMERIC_EPOCH) ? value.to_i : parsed_epoch_ms(value)
    end
  end

  # Converted through a Rational rather than a Float so the millisecond never rounds above
  # the one ClickHouse stored.
  #
  # `parse` answers nil for a string that is not a date at all, but raises on one whose
  # components are out of range — "mon out of range" for a thirteenth month — and a single
  # trigger may not fail a batch of thousands of which the dead letter queue would receive
  # only the first message.
  def parsed_epoch_ms(value)
    time = Time.find_zone!("UTC").parse(value)

    (time.to_time.to_r * 1000).to_i if time
  rescue ArgumentError
    nil
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

    trigger[:watermarks_ms].each_key.all? { caught_up_subscription_ids.include?(it) }
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
      .flat_map do |trigger|
        trigger[:watermarks_ms].map do |subscription_id, watermark_ms|
          {organization_id: trigger[:organization_id], subscription_id:, watermark_ms:}
        end
      end

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

    @paused_attempts += 1 if spend_attempt?

    if @paused_attempts > MAX_WATERMARK_ATTEMPTS
      give_up_on(offsets)
    else
      pause_on(offset)
    end
  end

  # A failed read is free for as long as it can still be a blip. Past that the wait is no
  # longer backpressure, and holding the offset would trade an unbounded lag for a trigger the
  # dead letter queue would have surfaced.
  def spend_attempt?
    if watermark_read_failed?
      @read_failures = @read_failures.to_i + 1

      return @read_failures > MAX_WATERMARK_READ_FAILURES
    end

    @read_failures = 0

    true
  end

  def pause_on(offset)
    index = batch.index { |message| message.offset == offset }

    mark_as_consumed(batch[index - 1]) if index.positive?

    pause(offset, WATERMARK_PAUSE_TIMEOUT)
  end

  # No other lane refreshes these customers, so a trigger whose buckets never landed is handed
  # to the dead letter queue instead of being dropped.
  #
  # The whole blocked set goes at once: pausing re-delivers the batch, so every one of them was
  # re-checked on every cycle and has waited exactly as long as the offset the budget was
  # counted on. Walking them one at a time would instead hold the partition for one budget per
  # blocked customer.
  #
  # `dispatch_to_dlq` is Karafka's own, from the route's dead letter queue: it builds the same
  # envelope and emits the same `dead_letter_queue.dispatched` event as an unprocessable
  # message, so both kinds of unprocessed trigger are replayed and monitored the same way.
  def give_up_on(offsets)
    blocked = offsets.to_set
    blocked_messages = batch.select { blocked.include?(it.offset) }

    Karafka.logger.warn(
      "#{self.class}: buckets still behind for #{blocked_messages.count} trigger(s) after " \
      "#{@paused_attempts} attempts, moving them to the dead letter queue"
    )

    blocked_messages.each { dispatch_to_dlq(it) }
    mark_as_consumed(blocked_messages.last)

    clear_pause_state
  end
end
