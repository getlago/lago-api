# frozen_string_literal: true

module RealtimeUsage
  # Reads the pre-aggregated usage of one subscription over one window from the ClickHouse
  # buckets. A failed read is a service failure, which leaves the caller reading events: an
  # unreachable ClickHouse has to make current usage slow, not broken, so the read never raises.
  class FetchBucketsService < BaseService
    Result = BaseResult[:usage_buckets]

    # One query must answer a plan mixing aggregation types, so the read selects every combine.
    # Keyed by the names the stream writes, the events processor's, without the `_agg` suffix.
    UNITS_BY_AGGREGATION_TYPE = {
      "max" => :max_units,
      "latest" => :latest_units
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

      result.usage_buckets = Events::Stores::UsageBucketSet.new(totals:, grouped_totals:, history_last_ingested_at:)
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
      window_rows.each_with_object({}) do |row, acc|
        key = [row[:charge_id], row[:charge_filter_id]]
        acc[key] = combine_totals(acc[key], row)
      end
    end

    def grouped_totals
      window_rows.each_with_object({}) do |row, acc|
        next if row[:groups].empty?

        groups = (acc[[row[:charge_id], row[:charge_filter_id]]] ||= {})
        groups[row[:groups]] = combine_totals(groups[row[:groups]], row)
      end
    end

    # A recurring charge sums every period since the subscription started, so a bucket of a closed
    # period ingested after the snapshot of that period has to send the charge back to the events.
    def history_last_ingested_at
      history_rows.each_with_object({}) do |row, acc|
        acc[row[:charge_id]] = [acc[row[:charge_id]], row[:last_ingested_at]].compact.max
      end
    end

    def combine_totals(totals, row)
      row_totals = Events::Stores::UsageBucketSet::Totals.new(
        aggregation_type: row[:aggregation_type],
        units: row[:units],
        events_count: row[:events_count],
        last_event_at: row[:last_event_at],
        precise_total_amount_cents: row[:precise_total_amount_cents]
      )

      totals ? totals.combine(row_totals) : row_totals
    end

    def window_rows
      rows.select { it[:in_window] }
    end

    def history_rows
      rows.reject { it[:in_window] }
    end

    def rows
      @rows ||= Events::Stores::Utils::ClickhouseConnection.with_retry { fetch_rows }
    end

    def fetch_rows
      scope
        .group(:charge_id, :charge_filter_id, :grouped_by, :aggregation_type, Arel.sql("in_window"))
        .pluck(Arel.sql(<<~SQL.squish))
          charge_id, charge_filter_id, grouped_by, aggregation_type,
          sum(units), max(units), argMax(units, last_event_at), max(last_event_at), sum(events_count),
          sum(precise_total_amount_cents), max(last_ingested_at),
          #{Clickhouse::UsageBucket.sanitize_sql_array(["bucket >= ?", window.begin])} AS in_window
        SQL
        .map do |charge_id, charge_filter_id, grouped_by, aggregation_type, sum_units, max_units, latest_units, last_event_at, events_count, precise_total_amount_cents, last_ingested_at, in_window|
          units = {sum_units:, max_units:, latest_units:}
            .fetch(UNITS_BY_AGGREGATION_TYPE.fetch(aggregation_type, :sum_units))

          {
            charge_id:,
            charge_filter_id:,
            groups: parse_groups(grouped_by),
            aggregation_type:,
            units: units.to_d,
            last_event_at: last_event_at.to_time,
            events_count: events_count.to_i,
            precise_total_amount_cents: precise_total_amount_cents.to_d,
            last_ingested_at: last_ingested_at.to_time,
            in_window: ActiveModel::Type::Boolean.new.cast(in_window)
          }
        end
    end

    # One read for both: the window of every charge, and the buckets before it of the recurring
    # charges, which only feed the late ingestion check.
    def scope
      buckets = Clickhouse::UsageBucket
        .where(organization_id: organization.id, subscription_id: subscription.id, charge_id: charge_ids)
        .where(bucket: ...window.end, is_deleted: 0)
      in_window = buckets.where(bucket: window.begin..)
      return in_window if recurring_charge_ids.empty?

      in_window.or(buckets.where(charge_id: recurring_charge_ids))
    end

    def charge_ids
      @charge_ids ||= charges.map(&:id)
    end

    def recurring_charge_ids
      @recurring_charge_ids ||= charges.select { it.billable_metric.recurring? }.map(&:id)
    end

    # The stream writes an absent group value as "", where the events store returns nil.
    def parse_groups(grouped_by)
      JSON.parse(grouped_by.presence || "{}").transform_values(&:presence)
    end

    # The pipeline attributes an event to a subscription only within its lifetime, so widening
    # the window to whole buckets cannot pull in usage from a neighbouring subscription.
    def window
      @window ||= Range.new(
        RealtimeUsage.floor_to_bucket(boundaries.charges_from_datetime),
        RealtimeUsage.ceil_to_bucket(boundaries.charges_to_datetime),
        true
      )
    end
  end
end
