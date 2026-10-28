# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # The span a report reads, and the periods it is cut into. Short spans read by the hour and
    # longer ones by the day, so a chart never carries more than a few dozen bars.
    class Window
      HOURLY_LIMIT = 48.hours
      MAX_DURATION = 31.days
      DEFAULT_DURATION = 24.hours

      GRANULARITIES = {"hour" => 1.hour, "day" => 1.day}.freeze

      attr_reader :timezone

      # The start of the longest window ending at to_datetime. It sits on a day wall, so every
      # read of the same day covers the same days, unless a DST change makes those days longer
      # than the maximum.
      def self.longest_from(to_datetime:, timezone:)
        to_datetime ||= Time.current

        Time.use_zone(timezone) do
          day_wall = to_datetime.in_time_zone(timezone).beginning_of_day - (MAX_DURATION - 1.day)
          [day_wall, to_datetime - MAX_DURATION].max
        end
      end

      def initialize(from_datetime:, to_datetime:, timezone:)
        @to_datetime = to_datetime || Time.current
        @from_datetime = from_datetime || (@to_datetime - DEFAULT_DURATION)
        @timezone = timezone
      end

      def errors
        return {from_datetime: ["invalid_window"]} if from_datetime >= to_datetime
        return {to_datetime: ["window_too_long"]} if to_datetime - from_datetime > MAX_DURATION

        {}
      end

      def granularity
        @granularity ||= (to_datetime - from_datetime > HOURLY_LIMIT) ? "day" : "hour"
      end

      # A bucket is summed whole, so both ends widen to the bucket wall they sit on rather than
      # cutting it. The start stays within a bucket of from_datetime even when the first period
      # opens earlier: a day read from 18:00 does not count the morning.
      def start_time
        @start_time ||= RealtimeUsage.floor_to_bucket(from_datetime)
      end

      def end_time
        @end_time ||= RealtimeUsage.ceil_to_bucket(to_datetime)
      end

      # Every period of the window, as the unix timestamps the reads return, so a period no
      # bucket fell in still gets its point.
      def periods
        @periods ||= begin
          walls = []
          wall = first_period

          while wall < end_time
            walls << wall.to_i
            wall += GRANULARITIES.fetch(granularity)
          end

          walls
        end
      end

      # Day walls move with DST, so they are computed in the timezone rather than by adding
      # seconds to the start.
      def period_sql(quoted_timezone)
        if granularity == "day"
          "toUnixTimestamp(toStartOfDay(bucket, #{quoted_timezone}))"
        else
          "toUnixTimestamp(toStartOfInterval(bucket, INTERVAL 1 hour, #{quoted_timezone}))"
        end
      end

      private

      attr_reader :from_datetime, :to_datetime

      # The first period wall at or before from_datetime, in the report's timezone — the same
      # instant ClickHouse groups the buckets on. The first period only holds what follows it.
      def first_period
        Time.use_zone(timezone) do
          time = from_datetime.in_time_zone(timezone)
          (granularity == "day") ? time.beginning_of_day : time.beginning_of_hour
        end
      end
    end
  end
end
