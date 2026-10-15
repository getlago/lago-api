# frozen_string_literal: true

module RealtimeUsage
  # Counts the events of a window and how many of them carry a transaction id the subscription
  # already sent, per metric code. Read from the raw events, which keep every insert: the enriched
  # table collapses the re-sent rows on merge, so the same window would stop reporting them the
  # moment a background merge ran.
  class CountDuplicateEventsService < BaseService
    Result = BaseResult[:events_count, :duplicates_count, :duplicates_by_code]

    def initialize(subscription:, codes:, from_datetime:, to_datetime:)
      @subscription = subscription
      @codes = codes
      @from_datetime = from_datetime
      @to_datetime = to_datetime

      super
    end

    def call
      rows = scope.group(:code).pluck(Arel.sql("code, count(), uniqExact(transaction_id)"))

      result.events_count = rows.sum { |_code, events_count, _transaction_ids| events_count }
      result.duplicates_by_code = rows.to_h { |code, events_count, transaction_ids| [code, events_count - transaction_ids] }
      result.duplicates_count = result.duplicates_by_code.values.sum
      result
    end

    private

    attr_reader :subscription, :codes, :from_datetime, :to_datetime

    def scope
      Clickhouse::EventsRaw.where(
        organization_id: subscription.organization_id,
        external_subscription_id: subscription.external_id,
        code: codes,
        timestamp: from_datetime..to_datetime
      )
    end
  end
end
