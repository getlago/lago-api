# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. A failed read is a service failure, which leaves the caller reading events: an
  # unreachable ClickHouse has to make current usage slow, not broken, so the read never raises.
  class FetchBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    # One query must answer a plan mixing aggregation types, so the read selects every combine.
    UNITS_BY_AGGREGATION_TYPE = {
      "max_agg" => :max_units,
      "latest_agg" => :latest_units
    }.freeze

    def initialize(subscription:, boundaries:, charges:)
      @subscription = subscription
      @boundaries = boundaries
      @charges = charges

      super
    end

    def call
      return result unless RealtimeUsage.enabled?(organization)
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
        acc[key] = combine_totals(acc[key], row)
      end
    end

    def grouped_totals
      rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[[row[:charge_id], row[:charge_filter_id]]] ||= {})
        groups[row[:groups]] = combine_totals(groups[row[:groups]], row)
      end
    end

    def combine_totals(totals, row)
      row_totals = Events::Stores::UsageBucketSet::Totals.new(
        aggregation_type: row[:aggregation_type],
        units: row[:units],
        events_count: row[:events_count],
        last_event_at: row[:last_event_at]
      )

      totals ? totals.combine(row_totals) : row_totals
    end

    def rows
      @rows ||= Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }
    end

    def fetch_rows
      Clickhouse::UsageBucket
        .where(organization_id: organization.id, subscription_id: subscription.id, charge_id: charge_ids)
        .where(bucket: window, is_deleted: 0)
        .group(:charge_id, :charge_filter_id, :grouped_by, :aggregation_type)
        .pluck(Arel.sql(<<~SQL.squish))
          charge_id, charge_filter_id, grouped_by, aggregation_type,
          sum(units), max(units), argMax(units, last_event_at), max(last_event_at), sum(events_count)
        SQL
        .map do |charge_id, charge_filter_id, grouped_by, aggregation_type, sum_units, max_units, latest_units, last_event_at, events_count|
          units = {sum_units:, max_units:, latest_units:}
            .fetch(UNITS_BY_AGGREGATION_TYPE.fetch(aggregation_type, :sum_units))

          {
            charge_id:,
            charge_filter_id:,
            groups: parse_groups(grouped_by),
            aggregation_type:,
            units: units.to_d,
            last_event_at: last_event_at.to_time,
            events_count: events_count.to_i
          }
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
