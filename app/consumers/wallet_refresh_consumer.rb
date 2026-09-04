# frozen_string_literal: true

# Refreshes the wallet ongoing balance as soon as its usage is queryable. Each realtime usage
# reaction consumes the shared trigger topic under its own group, so this pause stalls no other.
class WalletRefreshConsumer < ApplicationConsumer
  # Milliseconds. Pausing re-delivers the offset without holding the thread a sleep would.
  WATERMARK_PAUSE_TIMEOUT = 1_000

  # Past this age the sweep is the cheaper lane: a backlog drains at full speed instead of
  # being waited through one offset at a time.
  MAX_TRIGGER_AGE = 30.seconds

  # Pause cycles one offset may wait, so five minutes. Buckets that never land must neither
  # stall the partition nor vanish, so past this the trigger goes to the dead letter queue.
  MAX_WATERMARK_ATTEMPTS = 300

  # The adapter reports an unreachable server and a query that can no longer run as the same
  # error, so a failed read is free only this long before it spends the attempt budget too.
  MAX_WATERMARK_READ_FAILURES = 30

  # Epoch milliseconds, whole or decimal, as opposed to a rendered timestamp.
  NUMERIC_EPOCH = /\A\d+(?:\.\d+)?\z/

  # Caught rather than let out: the error would fail a batch of thousands, of which Karafka
  # dead-letters only the first message.
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

  # Karafka keeps the instance alive across batches, so per-batch state is rebuilt on every
  # `consume` rather than memoized.
  attr_reader :batch, :triggers, :stale_triggers, :refreshable_customers, :active_wallet_ids,
    :caught_up_subscription_ids

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

  # A pause re-delivers the whole batch, so without this every caught-up customer of it costs
  # a refresh per cycle. A watermark past the one refreshed is what usage ingested since is.
  def already_refreshed?(trigger)
    refreshed = refreshed_watermarks_ms[trigger[:customer_id]]

    return false if refreshed.nil?

    trigger[:watermarks_ms].all? { |subscription_id, watermark_ms| watermark_ms <= refreshed[subscription_id].to_i }
  end

  def refreshed_watermarks_ms
    @refreshed_watermarks_ms ||= {}
  end

  def clear_pause_state
    @paused_offset = nil
    @read_failures = 0
    @refreshed_watermarks_ms = nil
  end

  # One entry per customer, holding the highest watermark of each of its subscriptions: the
  # refresh reads them all, so waiting on one would debit the wallet against another's epoch.
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

    # The sink does not COALESCE `ingested_at`: there is no epoch to wait for, and refreshing
    # anyway would read the buckets early.
    if watermark_ms.nil?
      Karafka.logger.warn("#{self.class}: trigger without a watermark at offset #{message.offset}, skipped")

      return nil
    end

    {organization_id:, customer_id:, watermarks_ms: {subscription_id => watermark_ms}, offset: message.offset}
  end

  # Judged on first delivery only: a pause re-delivers the same timestamps, so judging again
  # would age out the very trigger being waited on, short of the dead letter queue.
  def stale?(message)
    return false if @paused_offset && message.offset >= @paused_offset

    message.timestamp < MAX_TRIGGER_AGE.ago
  end

  # Dropping a backlog is the policy, but a pipeline lagging past the window, or a producer
  # clock behind ours, otherwise looks exactly like silence.
  def log_stale_triggers
    return if stale_triggers.zero?

    Karafka.logger.warn(
      "#{self.class}: #{stale_triggers} trigger(s) older than #{MAX_TRIGGER_AGE.inspect}, left to the sweep"
    )
  end

  # The sink sends integer epoch milliseconds, already the unit compared. The other forms are
  # tolerated, truncated so the expectation never lands above the millisecond ClickHouse stored.
  def epoch_ms(value)
    case value
    when Numeric then value.to_i
    when String then value.match?(NUMERIC_EPOCH) ? value.to_i : parsed_epoch_ms(value)
    end
  end

  # Through a Rational so the millisecond never rounds above the stored one. `parse` raises on
  # components out of range, and one trigger may not fail a batch of thousands.
  def parsed_epoch_ms(value)
    time = Time.zone.parse(value)

    (time.to_time.to_r * 1000).to_i if time
  rescue ArgumentError
    nil
  end

  # One query for the whole batch. No active wallet, a tax error, or an organization off the
  # rollout each make the refresh a no-op, so none of them is worth dispatching.
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

  # One query for the whole batch. The wallet ids let the job run for a customer the sweep has
  # not flagged, so this lane does not ride on the sweep's bookkeeping.
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

  # Only the customers a refresh could act on are worth a watermark: the others would pause
  # the partition for a refresh never dispatched.
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

  # The attempt count lives here because Karafka resets its own pause tracker after every
  # successful `consume`.
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

  # A failed read is free while it can still be a blip. Past that, holding the offset trades an
  # unbounded lag for a trigger the dead letter queue would have surfaced.
  def spend_attempt?
    if watermark_read_failed?
      @read_failures = @read_failures.to_i + 1

      return @read_failures > MAX_WATERMARK_READ_FAILURES
    end

    @read_failures = 0

    true
  end

  # Resuming re-delivers from the blocked offset: nothing before it may stay uncommitted, and
  # nothing at or after it may be committed.
  def pause_on(offset)
    index = batch.index { |message| message.offset == offset }

    mark_as_consumed(batch[index - 1]) if index.positive?

    pause(offset, WATERMARK_PAUSE_TIMEOUT)
  end

  # No other lane refreshes these customers, so the trigger is dead-lettered rather than
  # dropped, the whole blocked set at once: they have all waited the same and cost a budget each.
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
