# frozen_string_literal: true

module RealtimeUsage
  # Counts the enriched events of a window and how many of them the events store collapses at
  # read time. The stream collapses on a different key, so duplicates explain a difference the
  # pipeline is not responsible for.
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
      events_by_code = scope.group(:code).count
      deduplicated_by_code = deduplicated_scope.group(:code).count

      result.events_count = events_by_code.values.sum
      result.duplicates_by_code = events_by_code.to_h { |code, count| [code, count - deduplicated_by_code.fetch(code, 0)] }
      result.duplicates_count = result.duplicates_by_code.values.sum
      result
    end

    private

    attr_reader :subscription, :codes, :from_datetime, :to_datetime

    def scope
      Clickhouse::EventsEnriched.where(
        organization_id: subscription.organization_id,
        external_subscription_id: subscription.external_id,
        code: codes,
        timestamp: from_datetime..to_datetime
      )
    end

    # FINAL collapses the rows sharing the sorting key, exactly as the events store reads them.
    def deduplicated_scope
      scope.from("events_enriched FINAL")
    end
  end
end
