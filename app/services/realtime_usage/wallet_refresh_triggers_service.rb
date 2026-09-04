# frozen_string_literal: true

module RealtimeUsage
  # One refresh trigger per customer out of a poll batch, carrying the highest ingestion
  # watermark of each of that customer's subscriptions.
  class WalletRefreshTriggersService < BaseService
    Result = BaseResult[:triggers, :stale_count]

    # Past this age the five-minute sweep is the cheaper lane: a backlog drains at full speed
    # instead of being waited through one offset at a time.
    MAX_TRIGGER_AGE = 30.seconds

    # Epoch milliseconds, whole or decimal, as opposed to a rendered timestamp.
    NUMERIC_EPOCH = /\A\d+(?:\.\d+)?\z/

    # @param messages [Array] the poll batch, each entry answering `payload`, `timestamp` and
    #   `offset`
    # @param paused_offset [Integer, nil] the offset the partition is currently paused on
    def initialize(messages:, paused_offset: nil)
      @messages = messages
      @paused_offset = paused_offset

      super
    end

    def call
      @stale_count = 0

      result.triggers = build_triggers
      result.stale_count = @stale_count
      result
    end

    private

    attr_reader :messages, :paused_offset

    # One entry per customer, holding the highest watermark of each of its subscriptions: the
    # refresh reads them all, so waiting on one would debit the wallet against another's epoch.
    def build_triggers
      messages.each_with_object({}) do |message, acc|
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
        @stale_count += 1

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
      return false if paused_offset && message.offset >= paused_offset

      message.timestamp < MAX_TRIGGER_AGE.ago
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
  end
end
