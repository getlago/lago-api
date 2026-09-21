# frozen_string_literal: true

module RealtimeUsage
  class HourlyBreakdownService < BaseService
    Result = BaseResult[:usage]

    Usage = Struct.new(:from_datetime, :to_datetime, :timezone, :aggregation_type, :last_ingested_at, :filters, :hours)
    Filter = Struct.new(:charge_filter_id, :charge_filter, :units, :events_count, :other)
    Hour = Struct.new(:time, :units, :events_count, :usages)
    HourUsage = Struct.new(:charge_filter_id, :units, :events_count, :other)

    MAX_WINDOW = 31.days

    SUMMABLE_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze

    # Every hour of the window carries every series, so a charge with thousands of filters
    # would build millions of points for a chart that can only draw a legend. The biggest
    # filters keep their own series and the tail folds into one, which keeps the hours
    # summing to the window total.
    MAX_FILTERS = 20

    # The stream writes the charge default as an empty filter id, so the folded series needs
    # a key no filter id can take.
    OTHER_KEY = "__other__"

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

      filters = build_filters

      result.usage = Usage.new(
        window_start,
        window_end,
        timezone,
        charge.billable_metric.aggregation_type,
        filter_totals.filter_map { |row| row[:last_ingested_at] }.max,
        filters,
        hours(filters)
      )
      result
    rescue *READ_ERRORS => e
      Sentry.capture_exception(e)
      result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
    end

    private

    attr_reader :subscription, :charge, :from_datetime, :to_datetime

    # The same gate the event store provider applies, narrowed to the aggregations whose hours
    # add up: summing per-bucket maxes or latest values would report a number nothing counted.
    def servable?
      RealtimeUsage.enabled?(subscription.organization) &&
        RealtimeUsage.supported_charge?(charge) &&
        SUMMABLE_AGGREGATION_TYPES.include?(charge.billable_metric.aggregation_type)
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
        seconds = BUCKET_DURATION.to_i

        aligned?(to_datetime) ? to_datetime : Time.zone.at(to_datetime.to_i - (to_datetime.to_i % seconds) + seconds)
      end
    end

    def aligned?(time)
      (time.to_i % BUCKET_DURATION.to_i).zero? && time.usec.zero?
    end

    # Every filter with usage in the window, biggest first, so the caller can assign colors by
    # rank once. Past MAX_FILTERS the tail becomes a single "other" series carrying its totals.
    # The charge default (no filter) carries a nil id, as does the folded series, which the
    # `other` flag tells apart.
    def build_filters
      charge_filters = charge.filters.includes(values: :billable_metric_filter).index_by(&:id)

      totals = filter_totals.map do |row|
        Filter.new(row[:charge_filter_id], charge_filters[row[:charge_filter_id]], row[:units], row[:events_count], false)
      end.sort_by { |filter| [-filter.units, filter.charge_filter_id.to_s] }

      return totals if totals.size <= MAX_FILTERS

      tail = totals.drop(MAX_FILTERS)

      totals.first(MAX_FILTERS) << Filter.new(nil, nil, tail.sum(&:units), tail.sum(&:events_count), true)
    end

    def hours(filters)
      by_hour = hour_rows(filters).group_by { |row| row[:hour] }
      keys = filters.map { |filter| filter.other ? OTHER_KEY : filter.charge_filter_id }

      hour_walls.map do |wall|
        rows_by_key = (by_hour[wall] || []).index_by { |row| row[:key] }

        usages = filters.zip(keys).map do |filter, key|
          row = rows_by_key[key]
          HourUsage.new(filter.charge_filter_id, row ? row[:units] : BigDecimal(0), row ? row[:events_count] : 0, filter.other)
        end

        Hour.new(wall, usages.sum(&:units), usages.sum(&:events_count), usages)
      end
    end

    # One row per filter, which bounds the read by the filters of the charge rather than by
    # the hours of the window.
    def filter_totals
      @filter_totals ||= with_retry { fetch_filter_totals }
    end

    def fetch_filter_totals
      base_scope
        .group(:charge_filter_id)
        .pluck(Arel.sql("charge_filter_id, sum(units), sum(events_count), max(last_ingested_at)"))
        .map do |charge_filter_id, units, events_count, last_ingested_at|
          {
            charge_filter_id: charge_filter_id.presence,
            units: BigDecimal(units.to_s),
            events_count: events_count.to_i,
            last_ingested_at: last_ingested_at
          }
        end
    end

    # The hourly read groups the folded filters together in Clickhouse, so it returns at most
    # one row per hour and per served series whatever the cardinality of the charge.
    def hour_rows(filters)
      return [] if filters.empty?

      kept_ids = filters.reject(&:other).map { |filter| filter.charge_filter_id.to_s }

      with_retry { fetch_hour_rows(filters.any?(&:other) ? kept_ids : nil) }
    end

    def fetch_hour_rows(kept_ids)
      base_scope
        .group(Arel.sql("hour, filter_key"))
        .pluck(Arel.sql(<<~SQL.squish))
          toUnixTimestamp(toStartOfInterval(bucket, INTERVAL 1 hour, #{quote(timezone)})) AS hour,
          #{filter_key(kept_ids)} AS filter_key,
          sum(events_count),
          sum(units)
        SQL
        .map do |hour, key, events_count, units|
          {
            hour: Time.zone.at(hour.to_i),
            key: (key == OTHER_KEY) ? OTHER_KEY : key.presence,
            events_count: events_count.to_i,
            units: BigDecimal(units.to_s)
          }
        end
    end

    def filter_key(kept_ids)
      return "charge_filter_id" if kept_ids.nil?

      "if(charge_filter_id IN (#{kept_ids.map { |id| quote(id) }.join(", ")}), charge_filter_id, #{quote(OTHER_KEY)})"
    end

    def base_scope
      Clickhouse::UsageBucket
        .where(
          organization_id: subscription.organization_id,
          subscription_id: subscription.id,
          charge_id: charge.id
        )
        .where("bucket >= ? AND bucket < ?", window_start, window_end)
    end

    def quote(value)
      Clickhouse::UsageBucket.connection.quote(value)
    end

    def with_retry(&)
      Events::Stores::Utils::ClickhouseConnection.with_retry(&)
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
