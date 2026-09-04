# frozen_string_literal: true

# Refreshes the wallet ongoing balance as soon as its usage is queryable. Each realtime usage
# reaction consumes the shared trigger topic under its own group, so this pause stalls no other.
class WalletRefreshConsumer < ApplicationConsumer
  # Milliseconds. Pausing re-delivers the offset without holding the thread a sleep would.
  WATERMARK_PAUSE_TIMEOUT = 1_000

  # Pause cycles one offset may wait. The partition is keyed by customer, so every cycle spent
  # on one customer is a cycle every other customer on it waits too: past this grace the sweep
  # is the better lane for the one still behind.
  MAX_WATERMARK_ATTEMPTS = 5

  # The adapter reports an unreachable server and a query that can no longer run as the same
  # error, so a failed read is free only this long before it spends the grace too.
  MAX_WATERMARK_READ_FAILURES = 5

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

    parsed = RealtimeUsage::WalletRefreshTriggersService.call!(messages: batch, paused_offset: @paused_offset)
    @triggers = parsed.triggers

    log_stale_triggers(parsed.stale_count)

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
  attr_reader :batch, :triggers, :refreshable_customers, :active_wallet_ids, :caught_up_subscription_ids

  def dispatch_refreshes
    refreshable = RealtimeUsage::RefreshableCustomersService.call!(triggers:)

    @refreshable_customers = refreshable.customers
    @active_wallet_ids = refreshable.active_wallet_ids
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

  # Dropping a backlog is the policy, but a pipeline lagging past the window, or a producer
  # clock behind ours, otherwise looks exactly like silence.
  def log_stale_triggers(count)
    return if count.zero?

    Karafka.logger.warn(
      "#{self.class}: #{count} trigger(s) older than " \
      "#{RealtimeUsage::WalletRefreshTriggersService::MAX_TRIGGER_AGE.inspect}, left to the sweep"
    )
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
      leave_to_sweep(offsets)
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

  # Waiting longer would hold every other customer on the partition for a wait only these ones
  # need. Ingestion flags the customer, so the five-minute sweep still covers the refresh.
  def leave_to_sweep(offsets)
    blocked = offsets.to_set
    blocked_messages = batch.select { blocked.include?(it.offset) }

    Karafka.logger.warn(
      "#{self.class}: buckets still behind for #{blocked_messages.count} trigger(s) after " \
      "#{@paused_attempts} attempts, left to the sweep"
    )

    mark_as_consumed(blocked_messages.last)

    clear_pause_state
  end
end
