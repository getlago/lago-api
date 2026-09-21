# frozen_string_literal: true

module RealtimeUsage
  # One refresh trigger per customer out of a poll batch, carrying the highest ingestion
  # watermark of each of that customer's subscriptions.
  class WalletRefreshTriggersService < BaseService
    Result = BaseResult[:triggers, :stale_count]

    # Past this age the five-minute sweep is the cheaper lane: a backlog drains at full speed
    # instead of being waited through one batch at a time.
    MAX_TRIGGER_AGE = 30.seconds

    # @param messages [Array] the poll batch, each entry answering `payload`, `timestamp` and
    #   `offset`
    def initialize(messages:)
      @messages = messages

      super
    end

    def call
      @stale_count = 0

      result.triggers = build_triggers
      result.stale_count = @stale_count
      result
    end

    private

    attr_reader :messages

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
      watermark_ms = payload["last_ingested_at"]

      return nil if organization_id.blank? || customer_id.blank? || subscription_id.blank?

      if message.timestamp < MAX_TRIGGER_AGE.ago
        @stale_count += 1

        return nil
      end

      # The sink sends integer epoch milliseconds, already the unit compared, and does not
      # COALESCE `ingested_at`: anything else carries no epoch to wait for, and refreshing
      # anyway would read the buckets early.
      unless watermark_ms.is_a?(Numeric)
        Karafka.logger.warn("#{self.class}: trigger without an integer watermark at offset #{message.offset}, skipped")

        return nil
      end

      {organization_id:, customer_id:, watermarks_ms: {subscription_id => watermark_ms.to_i}}
    end
  end
end
