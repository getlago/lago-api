# frozen_string_literal: true

module RealtimeUsage
  module Reports
    class EventsService < BaseService
      Result = BaseResult[:events]

      Events = Struct.new(:from_datetime, :to_datetime, :timezone, :time_granularity, :last_ingested_at, :events_count, :points)
      Point = Struct.new(:time, :events_count)

      def call
        validate_request
        return result unless result.success?

        rescue_read_errors do
          counts = with_retry { fetch_counts }.to_h

          result.events = Events.new(
            window.start_time,
            window.end_time,
            window.timezone,
            window.granularity,
            with_retry { base_scope.maximum(:last_ingested_at) },
            counts.values.sum,
            window.periods.map { |period| Point.new(Time.zone.at(period), counts.fetch(period, 0)) }
          )
          result
        end
      end

      private

      # An event lands in the bucket of every charge reading its metric on the subscription, so
      # a plan charging the same metric twice would count it twice. Within a bucket, the charges
      # of one metric read the same events, which the max keeps once.
      def fetch_counts
        per_charge = base_scope
          .group(:bucket, :subscription_id, :code, :charge_id)
          .select("bucket, subscription_id, code, sum(events_count) AS events_count")
          .to_sql

        Clickhouse::UsageBucket.connection.select_rows(<<~SQL.squish).map { |period, count| [period.to_i, count.to_i] }
          SELECT period, sum(events_count)
          FROM (
            SELECT #{period_sql} AS period, max(events_count) AS events_count
            FROM (#{per_charge})
            GROUP BY bucket, subscription_id, code
          )
          GROUP BY period
        SQL
      end
    end
  end
end
