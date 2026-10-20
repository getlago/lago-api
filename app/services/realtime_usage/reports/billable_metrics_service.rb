# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # The units of each metric over the window, per period and stacked by dimension. Every
    # metric of a page is answered by the same reads.
    class BillableMetricsService < BaseService
      Result = BaseResult[:billable_metrics]

      Report = Struct.new(
        :billable_metric, :from_datetime, :to_datetime, :timezone, :time_granularity, :units, :dimensions, :points
      )
      Dimension = Struct.new(:key, :name, :values, :units, :other)
      Point = Struct.new(:time, :units, :breakdown)
      PointUsage = Struct.new(:dimension_key, :units)

      # A stacked bar stays readable with a handful of colors. The biggest dimensions keep their
      # own series and the tail folds into one, which keeps every period summing to its total.
      # A max or latest metric reads its window total on the whole window, so its periods do not
      # add up to it.
      MAX_DIMENSIONS = 5

      # The charge default has an empty key, so the folded series needs one no dimension can take.
      OTHER_KEY = "__other__"

      def initialize(billable_metrics:, dimension_keys: nil, **)
        @billable_metrics = billable_metrics.select do |billable_metric|
          SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
        end
        @dimension_keys = dimension_keys.presence

        super(**)
      end

      def call
        validate_request
        return result unless result.success?

        rescue_read_errors do
          result.billable_metrics = billable_metrics.empty? ? [] : build_reports
          result
        end
      end

      private

      attr_reader :billable_metrics, :dimension_keys

      def build_reports
        dimension_key = dimension_key_for(billable_metrics.map(&:code))
        totals = dimension_totals(billable_metrics:, dimension_key:, dimension_keys:).group_by { |row| row[:code] }
        dimensions = totals.transform_values { |rows| build_dimensions(rows, dimension_key) }
        periods = period_rows(dimension_key, dimensions)

        billable_metrics.map do |billable_metric|
          metric_dimensions = dimensions.fetch(billable_metric.code, [])

          Report.new(
            billable_metric,
            window.start_time,
            window.end_time,
            window.timezone,
            window.granularity,
            metric_dimensions.sum(BigDecimal(0), &:units),
            metric_dimensions,
            points(metric_dimensions, periods[billable_metric.code] || {})
          )
        end
      end

      # Biggest first, so the caller can assign colors by rank once.
      def build_dimensions(rows, dimension_key)
        sorted = rows.sort_by { |row| [-row[:units], row[:dimension]] }.map do |row|
          dimension = dimension_key.dimension(row[:dimension])
          Dimension.new(row[:dimension], dimension.name, dimension.values, row[:units], false)
        end

        return sorted if sorted.size <= MAX_DIMENSIONS

        tail = sorted.drop(MAX_DIMENSIONS)
        sorted.first(MAX_DIMENSIONS) << Dimension.new(OTHER_KEY, nil, {}, tail.sum(BigDecimal(0), &:units), true)
      end

      def points(dimensions, rows)
        window.periods.map do |period|
          breakdown = dimensions.map do |dimension|
            PointUsage.new(dimension.key, rows.dig(period, dimension.key) || BigDecimal(0))
          end

          Point.new(Time.zone.at(period), breakdown.sum(BigDecimal(0), &:units), breakdown)
        end
      end

      # The folded dimensions are grouped together in ClickHouse, so the read returns at most one
      # row per metric, period and served series whatever the cardinality of the dimensions.
      def period_rows(dimension_key, dimensions)
        return {} if dimensions.empty?

        rows = usage_rows(
          billable_metrics:,
          dimension_key:,
          dimension_keys:,
          by_period: true,
          series_sql: series_sql(dimensions)
        )

        rows.each_with_object({}) do |(code, period, key, units), by_code|
          ((by_code[code] ||= {})[period] ||= {})[key] = units
        end
      end

      def series_sql(dimensions)
        folded = dimensions.values.any? { |metric_dimensions| metric_dimensions.any?(&:other) }
        return "dimension" unless folded

        kept = dimensions.flat_map do |code, metric_dimensions|
          metric_dimensions.reject(&:other).map { |dimension| "(#{quote(code)}, #{quote(dimension.key)})" }
        end

        "if((code, dimension) IN (#{kept.join(", ")}), dimension, #{quote(OTHER_KEY)})"
      end
    end
  end
end
