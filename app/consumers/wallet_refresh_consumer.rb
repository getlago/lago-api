# frozen_string_literal: true

# Pulls the wallet ongoing-balance refresh forward from the five-minute sweep. The pipeline
# emits one trigger per enriched count/sum event, keyed by (organization_id, customer_id).
#
# The trigger topic is shared by every realtime usage reaction, so each reaction gets its own
# consumer group: this one pauses its partition on the bucket watermark, and a group per
# reaction keeps that wait from stalling the others.
#
# The Redis flag-and-sweep lane stays authoritative and this consumer adds no bookkeeping of
# its own: it dispatches the very same `Customers::RefreshWalletJob`, whose uniqueness lock
# and `awaiting_wallet_refresh` guard collapse both lanes into one refresh per flagged epoch.
# Every trigger dropped here is therefore still owned by the sweep, which is what lets this
# consumer drop freely rather than wait.
class WalletRefreshConsumer < ApplicationConsumer
  # Milliseconds. Pausing re-delivers the offset without holding a worker thread, where a
  # sleep would hold the thread and the partition for as long as it ran.
  WATERMARK_PAUSE_TIMEOUT = 1_000

  # Past this age the sweep is the cheaper lane, so a trigger is dropped instead of waited
  # on, which is also what keeps a seeded backlog draining at full speed instead of pausing
  # through it.
  MAX_TRIGGER_AGE = 10.seconds

  # How many times one offset may pause before the sweep is left to it. `MAX_TRIGGER_AGE` is
  # measured on the pipeline's clock, so a producer running ahead of us would age no trigger
  # out and pause the partition forever; this bound is counted here and cannot be skewed away.
  MAX_WATERMARK_ATTEMPTS = 10

  # A failed read cannot tell caught-up buckets from late ones, and every trigger is owned by
  # the sweep anyway, so a ClickHouse outage waits and then drops. Letting the error out would
  # instead walk the whole topic into the dead letter queue one message per batch.
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
    @caught_up_subscription_ids = fetch_caught_up_subscription_ids

    blocked_offsets = []

    triggers.each_value do |trigger|
      customer = refreshable_customers[trigger[:customer_id]]
      next if customer.nil?

      if caught_up_subscription_ids.include?(trigger[:subscription_id])
        Customers::RefreshWalletJob.perform_later(customer)
      else
        blocked_offsets << trigger[:offset]
      end
    end

    wait_for_buckets(blocked_offsets.min) if blocked_offsets.any?
  end

  private

  # Karafka keeps the consumer instance alive across batches (`consumer_persistence`), so the
  # per-batch state is rebuilt on every `consume` instead of being memoized.
  attr_reader :batch, :triggers, :refreshable_customers, :caught_up_subscription_ids

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
    return nil if watermark_ms.nil?
    return nil if message.timestamp < MAX_TRIGGER_AGE.ago

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

  # One query for the whole batch, over the sweep's own scope: a trigger for a customer the
  # sweep would not pick up costs nothing here either. Organizations outside the realtime
  # usage rollout are dropped because their refresh does not read the buckets, so there is no
  # watermark for this consumer to be waiting on.
  def fetch_refreshable_customers
    Customer
      .with_active_wallets
      .awaiting_wallet_refresh
      .without_tax_errors
      .includes(:organization)
      .where(organization_id: triggers.each_value.map { it[:organization_id] }.uniq, id: triggers.keys)
      .distinct
      .index_by(&:id)
      .select { |_id, customer| RealtimeUsage.enabled?(customer.organization) }
  end

  # Only the customers the sweep would pick up are worth a watermark: the others are not
  # refreshed whatever the buckets hold, so waiting on them would pause the partition for a
  # refresh that is never dispatched.
  def fetch_caught_up_subscription_ids
    watermarks = triggers
      .each_value
      .select { refreshable_customers.key?(it[:customer_id]) }
      .map { it.slice(:organization_id, :subscription_id, :watermark_ms) }

    return Set.new if watermarks.empty?

    RealtimeUsage::BucketWatermarkService.call!(watermarks:).caught_up_subscription_ids
  rescue *CLICKHOUSE_ERRORS => e
    Karafka.logger.warn("WalletRefreshConsumer: bucket watermark read failed (#{e.class}), waiting")

    Set.new
  end

  # Resuming re-delivers from the blocked offset, so nothing before it may stay uncommitted
  # and nothing at or after it may be committed. Karafka skips its own automatic marking once
  # the partition is manually paused, and resumes it once the pausing stops, which is how
  # giving up lets the partition move past an offset whose buckets never landed.
  #
  # The attempt count lives on the consumer because Karafka resets its own pause tracker after
  # every successful `consume`. It only bounds the wait where the instance outlives the batch,
  # which is everywhere but development; there `MAX_TRIGGER_AGE` remains the only bound.
  def wait_for_buckets(offset)
    if offset == @paused_offset
      @paused_attempts += 1
    else
      @paused_offset = offset
      @paused_attempts = 1
    end

    if @paused_attempts > MAX_WATERMARK_ATTEMPTS
      Karafka.logger.warn("WalletRefreshConsumer: buckets still behind at offset #{offset}, leaving it to the sweep")

      @paused_offset = nil
    else
      index = batch.index { |message| message.offset == offset }

      mark_as_consumed(batch[index - 1]) if index.positive?

      pause(offset, WATERMARK_PAUSE_TIMEOUT)
    end
  end
end
