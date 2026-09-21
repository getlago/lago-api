# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. A failed read is a service failure, which leaves the caller reading events: an
  # unreachable ClickHouse has to make current usage slow, not broken, so the read never raises.
  class FetchBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    BUCKET_DURATION = 15.minutes

    # What the ClickHouse driver raises on a connection it cannot use, plus the two errors the
    # retry helper and the row mapping raise on their own.
    READ_ERRORS = [
      *Events::Stores::Utils::ClickhouseConnection::RETRYABLE_ERRORS,
      Events::Stores::Clickhouse::MemoryLimitError,
      JSON::ParserError
    ].freeze

    def initialize(subscription:, boundaries:, charges:)
      @subscription = subscription
      @boundaries = boundaries
      @charges = charges

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)
      return result if RealtimeUsage.deduplicated?(organization)
      return result if charges.empty?

      result.usage_buckets = Events::Stores::UsageBucketSet.new(totals:, grouped_totals:)
      result
    rescue *READ_ERRORS => e
      Sentry.capture_exception(e)
      result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
    end

    private

    attr_reader :subscription, :boundaries, :charges

    def organization
      @organization ||= subscription.organization
    end

    def totals
      rows.each_with_object({}) do |row, acc|
        key = [row[:charge_id], row[:charge_filter_id]]
        acc[key] = sum_totals(acc[key], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[[row[:charge_id], row[:charge_filter_id]]] ||= {})
        groups[row[:groups]] = sum_totals(groups[row[:groups]], row)
      end
    end

    def sum_totals(totals, row)
      Events::Stores::UsageBucketSet::Totals.new(
        units: (totals&.units || BigDecimal(0)) + row[:units],
        events_count: (totals&.events_count || 0) + row[:events_count]
      )
    end

    def rows
      @rows ||= Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }
    end

    def fetch_rows
      Clickhouse::UsageBucket
        .where(organization_id: organization.id, subscription_id: subscription.id, charge_id: charge_ids)
        .where(bucket: window, is_deleted: 0)
        .group(:charge_id, :charge_filter_id, :grouped_by)
        .pluck(Arel.sql("charge_id, charge_filter_id, grouped_by, sum(units), sum(events_count)"))
        .map do |charge_id, charge_filter_id, grouped_by, units, events_count|
          {charge_id:, charge_filter_id:, groups: parse_groups(grouped_by), units: units.to_d, events_count: events_count.to_i}
        end
    end

    def charge_ids
      @charge_ids ||= charges.map(&:id)
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end

    # The pipeline attributes an event to a subscription only within its lifetime, so widening
    # the window to whole buckets cannot pull in usage from a neighbouring subscription.
    def window
      @window ||= floor_to_bucket(boundaries.charges_from_datetime)...ceil_to_bucket(boundaries.charges_to_datetime)
    end

    def floor_to_bucket(time)
      Time.zone.at(time.to_i - (time.to_i % BUCKET_DURATION.to_i))
    end

    def ceil_to_bucket(time)
      floor = floor_to_bucket(time)

      (floor == time) ? floor : floor + BUCKET_DURATION
    end
  end
end
