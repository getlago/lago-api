# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # The organization-wide reads behind the real-time usage pages. They answer from the usage
    # buckets alone, so they only see the events the stream matched to a served charge.
    class BaseService < ::BaseService
      SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg max_agg latest_agg].freeze

      # A customer or subscription filter is a list of ids, as one external id can name several
      # records over time (a deleted customer, a terminated subscription).
      def initialize(organization:, from_datetime: nil, to_datetime: nil, customer_ids: nil, subscription_ids: nil)
        @organization = organization
        @customer_ids = customer_ids
        @subscription_ids = subscription_ids
        @window = Window.new(from_datetime:, to_datetime:, timezone: organization.timezone)

        super
      end

      private

      attr_reader :organization, :customer_ids, :subscription_ids, :window

      def validate_request
        return result.forbidden_failure! unless RealtimeUsage.enabled?(organization)

        errors = window.errors
        result.validation_failure!(errors:) if errors.present?
      end

      # The sink tombstones a row it has retracted, which the engine only drops on a merge, so
      # every read leaves the deleted rows out itself.
      def base_scope
        scope = Clickhouse::UsageBucket
          .where(organization_id: organization.id, is_deleted: 0)
          .where("bucket >= ? AND bucket < ?", window.start_time, window.end_time)

        scope = scope.where(customer_id: customer_ids) unless customer_ids.nil?
        scope = scope.where(subscription_id: subscription_ids) unless subscription_ids.nil?
        scope
      end

      # Only the filters with usage in the window are loaded, which bounds the lookup by what was
      # counted rather than by every filter of the organization.
      def dimension_key_for(codes)
        charge_filter_ids = with_retry do
          base_scope.where(code: codes).where.not(charge_filter_id: "").distinct.pluck(:charge_filter_id)
        end

        DimensionKey.build(organization:, charge_filter_ids:)
      end

      # One row per metric and dimension, which bounds the read by the dimensions rather than by
      # the periods of the window.
      def dimension_totals(billable_metrics:, dimension_key:, dimension_keys: nil)
        usage_rows(billable_metrics:, dimension_key:, dimension_keys:)
          .map { |code, dimension, units| {code:, dimension:, units:} }
      end

      # Billing reads every subscription on its own, so the buckets are aggregated in three steps:
      # each charge as its metric aggregates (a max of maxes, the latest of the latest values),
      # then the charges of one metric on a subscription, which read the same events and are kept
      # once, then the subscriptions, which add up. The series fold last, so a folded max is still
      # the sum of real maxes.
      #
      # Returns [code, (period,) series, units] rows.
      def usage_rows(billable_metrics:, dimension_key:, dimension_keys: nil, keys: nil, by_period: false, series_sql: "dimension")
        codes = billable_metrics.map(&:code)
        scope = base_scope.where(code: codes)
        scope = scope.where("#{dimension_key.sql} IN (#{quote_list(dimension_keys)})") if dimension_keys
        scope = scope.where("#{dimension_key.sql} IN (#{quote_list(keys)})") if keys

        period = by_period ? "period, " : ""

        per_charge = scope
          .group(Arel.sql("code, subscription_id, charge_id, #{period}dimension"))
          .select(Arel.sql(<<~SQL.squish))
            code, subscription_id, #{"#{period_sql} AS period, " if by_period}
            #{dimension_key.sql} AS dimension, #{units_sql(billable_metrics)} AS value
          SQL
          .to_sql

        rows = with_retry do
          Clickhouse::UsageBucket.connection.select_rows(<<~SQL.squish)
            SELECT code, #{period}#{series_sql} AS series, sum(value)
            FROM (
              SELECT code, subscription_id, #{period}dimension, max(value) AS value
              FROM (#{per_charge})
              GROUP BY code, subscription_id, #{period}dimension
            )
            GROUP BY code, #{period}series
          SQL
        end

        rows.map do |row|
          *columns, units = row
          columns[1] = columns[1].to_i if by_period
          [*columns, BigDecimal(units.to_s)]
        end
      end

      # A bucket holds the max or the latest value of its 15 minutes, so a period or a window
      # takes the max of the maxes and the value of its latest bucket.
      def units_sql(billable_metrics)
        codes = billable_metrics.group_by(&:aggregation_type).transform_values { |metrics| metrics.map(&:code) }

        sql = "sum(units)"
        sql = "if(code IN (#{quote_list(codes["latest_agg"])}), argMax(units, last_event_at), #{sql})" if codes["latest_agg"]
        sql = "if(code IN (#{quote_list(codes["max_agg"])}), max(units), #{sql})" if codes["max_agg"]
        sql
      end

      def period_sql
        window.period_sql(quote(window.timezone))
      end

      def quote(value)
        Clickhouse::UsageBucket.connection.quote(value)
      end

      def quote_list(values)
        values.map { |value| quote(value) }.join(", ")
      end

      def with_retry(&)
        Events::Stores::Utils::ClickhouseConnection.with_retry(&)
      end

      def rescue_read_errors
        yield
      rescue *READ_ERRORS => e
        Sentry.capture_exception(e)
        result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
      end
    end
  end
end
