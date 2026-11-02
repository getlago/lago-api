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
        validate_billable_metric(billable_metric) if result.success?
        return result unless result.success?

        rescue_read_errors do
          dimension_key = dimension_key_for([billable_metric.code])

          result.dimensions = ranked_dimensions(billable_metrics: [billable_metric], dimension_key:, limit:)
            .map { |_code, key| Row.new(key, dimension_key.dimension(key).name) }
          result
        end
      end

      private

      attr_reader :billable_metric, :limit
    end
  end
end
