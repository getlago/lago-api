# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # The organization-wide reads behind the real-time usage pages. They answer from the usage
    # buckets alone, so they only see the events the stream matched to a served charge.
    class BaseService < ::BaseService
      include BucketReads

      def initialize(organization:, from_datetime: nil, to_datetime: nil, external_customer_id: nil, external_subscription_id: nil)
        @organization = organization
        @external_customer_id = external_customer_id
        @external_subscription_id = external_subscription_id
        @window = Window.new(from_datetime:, to_datetime:, timezone: organization.timezone)

        super
      end

      # The bucket pipeline leaves recurring metrics out, so they have no usage to report.
      def self.served?(billable_metric)
        SUPPORTED_AGGREGATION_TYPES.include?(billable_metric.aggregation_type) && !billable_metric.recurring?
      end

      private

      attr_reader :organization, :external_customer_id, :external_subscription_id, :window

      def validate_request
        return result.forbidden_failure! unless RealtimeUsage.enabled?(organization)

        errors = window.errors
        result.validation_failure!(errors:) if errors.present?
      end

      def validate_billable_metric(billable_metric)
        return if self.class.served?(billable_metric)

        result.single_validation_failure!(field: :billable_metric_code, error_code: "unsupported_aggregation_type")
      end

      # The folded series is cut from the dimensions of the whole window, so it names no usage a
      # filter could select.
      def validate_dimension_keys(dimension_keys)
        return unless dimension_keys&.include?(BillableMetricsService::OTHER_KEY)

        result.single_validation_failure!(field: :dimension_keys, error_code: "invalid_dimension_key")
      end

      # The sink tombstones a row it has retracted, which the engine only drops on a merge, so
      # every read leaves the deleted rows out itself.
      def base_scope
        scope = Clickhouse::UsageBucket
          .where(organization_id: organization.id, is_deleted: 0)
          .where("bucket >= ? AND bucket < ?", window.start_time, window.end_time)

        scope = scope.where(customer_id: customer_ids) if external_customer_id
        scope = scope.where(subscription_id: subscription_ids) if external_subscription_id
        scope
      end

      # Deleted customers and terminated subscriptions keep their buckets, so a filter matches
      # every record its external id named.
      def customer_ids
        @customer_ids ||= Customer.with_discarded.where(organization:, external_id: external_customer_id).ids
      end

      def subscription_ids
        @subscription_ids ||= organization.subscriptions.where(external_id: external_subscription_id).ids
      end

      # Only the filters with usage in the window are loaded, which bounds the lookup by what was
      # counted rather than by every filter of the organization.
      def dimension_key_for(codes)
        charge_filter_ids = with_retry do
          base_scope.where(code: codes).where.not(charge_filter_id: "").distinct.pluck(:charge_filter_id)
        end

        DimensionKey.build(organization:, charge_filter_ids:)
      end

      # The dimensions of each metric, biggest first, ranked and cut in ClickHouse so a page never
      # loads the tail. Every row also carries the units and the number of dimensions of its
      # metric, which the folded series and the pagination are built from.
      #
      # Returns [code, dimension, units, metric_units, dimensions_count] rows.
      def ranked_dimensions(billable_metrics:, dimension_key:, limit:, dimension_keys: nil, offset: 0)
        sql = usage_sql(billable_metrics:, dimension_key:, dimension_keys:)

        rows = with_retry do
          Clickhouse::UsageBucket.connection.select_rows(<<~SQL.squish)
            SELECT code, series, units, sum(units) OVER (PARTITION BY code), count() OVER (PARTITION BY code)
            FROM (#{sql})
            ORDER BY code, units DESC, series
            LIMIT #{offset.to_i}, #{limit.to_i} BY code
          SQL
        end

        rows.map do |code, dimension, units, metric_units, dimensions_count|
          [code, dimension, BigDecimal(units.to_s), BigDecimal(metric_units.to_s), dimensions_count.to_i]
        end
      end

      def dimensions_count(billable_metric:, dimension_key:, dimension_keys: nil)
        sql = usage_sql(billable_metrics: [billable_metric], dimension_key:, dimension_keys:)

        with_retry { Clickhouse::UsageBucket.connection.select_value("SELECT count() FROM (#{sql})").to_i }
      end

      # Returns [code, period, series, units] rows.
      def period_rows(billable_metrics:, dimension_key:, dimension_keys: nil, keys: nil, series_sql: "dimension")
        sql = usage_sql(billable_metrics:, dimension_key:, dimension_keys:, keys:, by_period: true, series_sql:)

        with_retry { Clickhouse::UsageBucket.connection.select_rows(sql) }.map do |code, period, series, units|
          [code, period.to_i, series, BigDecimal(units.to_s)]
        end
      end

      # Billing reads every subscription on its own, so the buckets are aggregated in two steps:
      # each subscription as its metric aggregates (a max of maxes, the latest of the latest
      # values), then the subscriptions, which add up. The series fold last, so a folded max is
      # still the sum of real maxes.
      #
      # The charges of one metric on a subscription each read every event of the metric, but can
      # split them on different dimensions: one per region, another not at all. Adding them up
      # would count the events twice, and keeping the biggest per dimension would count the
      # filtered ones twice, so a single charge is read per subscription, metric and bucket.
      #
      # Returns the SQL of [code, (period,) series, units] rows.
      def usage_sql(billable_metrics:, dimension_key:, dimension_keys: nil, keys: nil, by_period: false, series_sql: "dimension")
        codes = billable_metrics.map(&:code)
        metric_scope = base_scope.where(code: codes)

        scope = metric_scope.where("(code, subscription_id, bucket, charge_id) IN (#{read_charges_sql(metric_scope)})")
        scope = scope.where("#{dimension_key.sql} IN (#{quote_list(dimension_keys)})") if dimension_keys
        scope = scope.where("#{dimension_key.sql} IN (#{quote_list(keys)})") if keys

        period = by_period ? "period, " : ""

        per_subscription = scope
          .group(Arel.sql("code, subscription_id, #{period}dimension"))
          .select(Arel.sql(<<~SQL.squish))
            code, subscription_id, #{"#{period_sql} AS period, " if by_period}
            #{dimension_key.sql} AS dimension, #{units_sql(billable_metrics)} AS value
          SQL
          .to_sql

        <<~SQL.squish
          SELECT code, #{period}#{series_sql} AS series, sum(value) AS units
          FROM (#{per_subscription})
          GROUP BY code, #{period}series
        SQL
      end

      # The charge splitting the usage the finest, then the smallest id, ranked on the whole
      # window before any dimension filter, so every read of a report splits the usage the same
      # way. The pick is made per bucket: a plan override moves a subscription to new charges
      # without changing its id, and each half of the window keeps the charges it was read on.
      def read_charges_sql(scope)
        ranked = scope
          .select(<<~SQL.squish)
            code, subscription_id, bucket, charge_id,
            uniqExact(charge_filter_id, grouped_by) OVER (PARTITION BY code, subscription_id, charge_id) AS dimensions
          SQL
          .to_sql

        <<~SQL.squish
          SELECT code, subscription_id, bucket, argMin(charge_id, (-toInt64(dimensions), charge_id))
          FROM (#{ranked})
          GROUP BY code, subscription_id, bucket
        SQL
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

      def rescue_read_errors
        yield
      rescue *READ_ERRORS => e
        Sentry.capture_exception(e)
        result.service_failure!(code: "usage_buckets_read_failure", message: e.message, error: e)
      end
    end
  end
end
