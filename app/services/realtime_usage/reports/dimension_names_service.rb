# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # The dimensions of one metric, biggest first, without their periods: what a dimension filter
    # lists. With no start, it reads the longest window the reports allow, so the list does not
    # move with the range a page picked.
    class DimensionNamesService < BaseService
      Result = BaseResult[:dimensions]

      Row = Struct.new(:key, :name)

      DEFAULT_LIMIT = DimensionsService::MAX_LIMIT
      MAX_LIMIT = DimensionsService::MAX_LIMIT

      def initialize(organization:, billable_metric:, limit: nil, from_datetime: nil, to_datetime: nil, **)
        @billable_metric = billable_metric
        @limit = (limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
        from_datetime ||= Window.longest_from(to_datetime:, timezone: organization.timezone)

        super(organization:, from_datetime:, to_datetime:, **)
      end

      def call
        validate_request
        return result unless result.success?
        unless SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type)
          return result.single_validation_failure!(field: :billable_metric_code, error_code: "unsupported_aggregation_type")
        end

        rescue_read_errors do
          dimension_key = dimension_key_for([billable_metric.code])

          result.dimensions = dimension_totals(billable_metrics: [billable_metric], dimension_key:)
            .sort_by { |row| [-row[:units], row[:dimension]] }
            .first(limit)
            .map { |row| Row.new(row[:dimension], dimension_key.dimension(row[:dimension]).name) }
          result
        end
      end

      private

      attr_reader :billable_metric, :limit
    end
  end
end
