# frozen_string_literal: true

# Refreshes the wallet ongoing balance as soon as its usage is queryable. The refresh runs inline:
# throughput comes from the topic's partitions and Karafka's concurrency, not from a job queue.
class WalletRefreshConsumer < ApplicationConsumer
  # How long a batch waits for the buckets of the customers still behind. The topic is keyed by
  # customer, so a longer wait delays every other customer on the partition; past this grace the
  # sweep is the better lane for the ones still behind. A backlog never waits: its triggers are
  # older than the maximum age and never reach here.
  BUCKET_WAIT_TIMEOUT = 5.seconds
  BUCKET_WAIT_INTERVAL = 0.1

  # Refreshes run inline, so the batch has to be handed back well inside Kafka's poll interval
  # or the consumer is judged dead and the group rebalances.
  CONSUME_DEADLINE = 60.seconds

  # Seconds. Contention means the sweep is already refreshing this customer, so there is nothing
  # to wait for.
  LOCK_TIMEOUT = 0

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
    @deadline = CONSUME_DEADLINE.from_now
    @read_failure_logged = false

    parsed = RealtimeUsage::WalletRefreshTriggersService.call!(messages: messages.to_a)

    log_stale_triggers(parsed.stale_count)

    pending = refreshable_triggers(parsed.triggers)
    wait_deadline = BUCKET_WAIT_TIMEOUT.from_now

    until pending.empty?
      pending = refresh_caught_up(pending)

      break if pending.empty? || out_of_time? || Time.current >= wait_deadline

      sleep BUCKET_WAIT_INTERVAL
    end

    leave_to_sweep(pending)
  end

  private

  # Karafka keeps the instance alive across batches, so per-batch state is rebuilt on every
  # `consume` rather than memoized.
  attr_reader :customers

  # Only the customers a refresh could act on are worth a watermark: the others would hold the
  # batch for a refresh never dispatched.
  def refreshable_triggers(triggers)
    return [] if triggers.empty?

    @customers = RealtimeUsage::RefreshableCustomersService.call!(triggers:).customers

    triggers.each_value.select { customers.key?(it[:customer_id]) }
  end

  # Refreshes every customer whose buckets have landed, and returns the ones left waiting.
  def refresh_caught_up(pending)
    caught_up_subscription_ids = fetch_caught_up_subscription_ids(pending)

    # An unavailable ClickHouse cannot tell a late bucket from one that will never land, so the
    # whole batch keeps waiting rather than refreshing against an unknown epoch.
    return pending if caught_up_subscription_ids.nil?

    ready, behind = pending.partition do |trigger|
      trigger[:watermarks_ms].each_key.all? { caught_up_subscription_ids.include?(it) }
    end

    behind + refresh_all(ready)
  end

  # One read for the whole batch: a round-trip per customer would cost more time than the
  # ingestion this reacts to, and the set is re-read on every wait cycle.
  def fetch_caught_up_subscription_ids(pending)
    watermarks = pending.flat_map do |trigger|
      trigger[:watermarks_ms].map do |subscription_id, watermark_ms|
        {organization_id: trigger[:organization_id], subscription_id:, watermark_ms:}
      end
    end

    RealtimeUsage::BucketWatermarkService.call!(watermarks:).caught_up_subscription_ids
  rescue *CLICKHOUSE_ERRORS => e
    log_read_failure(e)

    nil
  end

  # Returns the triggers the deadline left untouched.
  def refresh_all(triggers)
    triggers.each_with_index do |trigger, index|
      return triggers.drop(index) if out_of_time?

      refresh(trigger)
    end

    []
  end

  # A failed refresh is left to the sweep rather than retried here: ingestion leaves the customer
  # flagged, and retrying would spend the partition on one customer.
  def refresh(trigger)
    customer = customers[trigger[:customer_id]]

    Customers::RefreshWalletsService.call!(customer:, force: true, lock_timeout_seconds: LOCK_TIMEOUT)
  rescue BaseLockService::FailedToAcquireLock
    nil
  rescue => e
    Karafka.logger.warn("#{self.class}: refresh failed for customer #{customer.id} (#{e.class}), left to the sweep")

    Sentry.capture_exception(e)
  end

  def out_of_time?
    Time.current >= @deadline || revoked? || Karafka::App.stopping?
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

  # Once per batch: the read is retried every `BUCKET_WAIT_INTERVAL`, and an outage would
  # otherwise write a line per cycle.
  def log_read_failure(error)
    return if @read_failure_logged

    @read_failure_logged = true

    Karafka.logger.warn("#{self.class}: bucket watermark read failed (#{error.class}), waiting")
  end

  # The batch is committed either way. Ingestion flags the customer, so the five-minute sweep
  # still covers every refresh this lane walks away from.
  def leave_to_sweep(pending)
    return if pending.empty?

    Karafka.logger.warn(
      "#{self.class}: #{pending.count} customer(s) still behind their watermark or out of time, left to the sweep"
    )
  end
end
