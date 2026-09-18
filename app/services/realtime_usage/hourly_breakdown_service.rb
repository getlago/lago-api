# frozen_string_literal: true

module RealtimeUsage
  class HourlyBreakdownService < BaseService
    Result = BaseResult[:usage]

    Usage = Struct.new(:from_datetime, :to_datetime, :timezone, :aggregation_type, :last_ingested_at, :filters, :hours)
    Filter = Struct.new(:charge_filter_id, :charge_filter, :units, :events_count)
    Hour = Struct.new(:time, :units, :events_count, :usages)
    HourUsage = Struct.new(:charge_filter_id, :units, :events_count)

    MAX_WINDOW = 31.days

    def initialize(subscription:, charge:, from_datetime: nil, to_datetime: nil)
      @subscription = subscription
      @charge = charge
      @to_datetime = to_datetime || Time.current
      @from_datetime = from_datetime || (@to_datetime - 24.hours)

      super
    end

    def call
      return result.forbidden_failure! unless servable?
      return result.validation_failure!(errors: {from_datetime: ["invalid_window"]}) if from_datetime >= to_datetime
      return result.validation_failure!(errors: {to_datetime: ["window_too_long"]}) if window_end > window_start + MAX_WINDOW

      rows = bucket_rows
      filters = build_filters(rows)

      result.usage = Usage.new(
        window_start,
        window_end,
        timezone,
        charge.billable_metric.aggregation_type,
        rows.filter_map { |row| row[:last_ingested_at] }.max,
        filters,
        hours(rows, filters)
      )
      result
    rescue *READ_ERRORS => e
      Sentry.capture_exception(e)
      result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
    end

    private

    attr_reader :subscription, :charge, :from_datetime, :to_datetime

    # The same three-part gate the event store provider applies: an organization whose store
    # drops duplicates would read units the buckets counted twice, and an unsupported charge
    # has no bucket to read at all.
    def servable?
      organization = subscription.organization

      RealtimeUsage.enabled?(organization) &&
        !RealtimeUsage.deduplicated?(organization) &&
        RealtimeUsage.supported_charge?(charge)
    end

    def timezone
      @timezone ||= subscription.customer.applicable_timezone
    end

    # The first hour wall at or before from_datetime, in the customer's
    # timezone — the same instant Clickhouse groups the buckets on.
    def window_start
      @window_start ||= Time.use_zone(timezone) { from_datetime.in_time_zone(timezone).beginning_of_hour }
    end

    # A bucket is summed whole, so an end inside one would report less than what was counted.
    # Both ends widen to the wall they sit on rather than cutting the bucket, and the window
    # the caller reads back is the span the units describe.
    def window_end
      @window_end ||= begin
        seconds = BUCKET_SIZE.to_i

        aligned?(to_datetime) ? to_datetime : Time.zone.at(to_datetime.to_i - (to_datetime.to_i % seconds) + seconds)
      end
    end

    def aligned?(time)
      (time.to_i % BUCKET_SIZE.to_i).zero? && time.usec.zero?
    end

    def bucket_rows
      Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }
    end

    def fetch_rows
      Clickhouse::UsageBucket
        .where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          charge_id: charge.id
        )
        .where("bucket >= ? AND bucket < ?", window_start, window_end)
        .group(Arel.sql("hour, charge_filter_id"))
        .pluck(Arel.sql(<<~SQL.squish))
          toUnixTimestamp(toStartOfInterval(bucket, INTERVAL 1 hour, #{Clickhouse::UsageBucket.connection.quote(timezone)})) AS hour,
          charge_filter_id,
          sum(events_count),
          sum(units),
          max(last_ingested_at)
        SQL
        .map do |hour, charge_filter_id, events_count, units, last_ingested_at|
          {
            hour: Time.zone.at(hour.to_i),
            charge_filter_id: charge_filter_id.presence,
            events_count: events_count.to_i,
            units: BigDecimal(units.to_s),
            last_ingested_at: last_ingested_at
          }
        end
    end

    # Every filter with usage in the window, biggest first, so the caller
    # can assign colors by rank once and fold the tail into an "other"
    # series. The charge default (no filter) carries a nil id.
    def build_filters(rows)
      charge_filters = charge.filters.includes(values: :billable_metric_filter).index_by(&:id)

      rows.group_by { |row| row[:charge_filter_id] }.map do |charge_filter_id, filter_rows|
        Filter.new(
          charge_filter_id,
          charge_filters[charge_filter_id],
          filter_rows.sum { |row| row[:units] },
          filter_rows.sum { |row| row[:events_count] }
        )
      end.sort_by { |filter| [-filter.units, filter.charge_filter_id.to_s] }
    end

    def hours(rows, filters)
      by_hour = rows.group_by { |row| row[:hour] }
      charge_filter_ids = filters.map(&:charge_filter_id)

      hour_walls.map do |wall|
        hour_rows = (by_hour[wall] || []).index_by { |row| row[:charge_filter_id] }

        usages = charge_filter_ids.map do |charge_filter_id|
          row = hour_rows[charge_filter_id]
          HourUsage.new(charge_filter_id, row ? row[:units] : BigDecimal(0), row ? row[:events_count] : 0)
        end

        Hour.new(wall, usages.sum(&:units), usages.sum(&:events_count), usages)
      end
    end

    def hour_walls
      walls = []
      wall = window_start

      while wall < window_end
        walls << wall
        wall += 1.hour
      end

      walls
    end
  end
end
