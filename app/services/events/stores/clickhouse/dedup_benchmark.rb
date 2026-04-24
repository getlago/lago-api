# frozen_string_literal: true

module Events
  module Stores
    module Clickhouse
      # Console-only harness. Compares the current argMax GROUP BY deduplication
      # against alternatives against whatever data lives in the connected
      # ClickHouse. Does NOT seed data and does NOT drop caches (both unsafe in prod).
      #
      # Each strategy's SQL is wrapped in the same CTE shape production uses
      # (see ClickhouseStore#events_cte_queries_with_deduplication):
      #
      #   WITH events_enriched AS (<strategy dedup sql>),
      #        events         AS (SELECT * FROM events_enriched [WHERE <post_dedup_where>])
      #   SELECT COALESCE(SUM(events.<sum_column>), 0) FROM events
      #
      # Execution, server-side metric collection and table printing are delegated
      # to Events::Stores::Utils::ClickhouseBenchmark. This service adds the
      # dedup-specific bits: building strategies, the correctness check, the
      # CTE+SUM wrapping and optional CSV output.
      #
      # Correctness check compares a scalar aggregate (cheap, representative of
      # the real query shape) rather than materialising the full dedup row set.
      # The measured query is the same wrapped form.
      #
      # Usage from `lago exec api bin/rails console`:
      #
      #   Events::Stores::Clickhouse::DedupBenchmark.call(
      #     subscription: Subscription.find("..."),
      #     boundaries: { from_datetime: 1.month.ago, to_datetime: Time.current },
      #     code: "<billable_metric_code>",
      #     sum_column: "decimal_value",
      #     post_dedup_where: "events.properties['region'] = 'eu'", # optional
      #     repetitions: 5
      #   )
      class DedupBenchmark < BaseService
        include Events::Stores::Utils::QueryHelpers

        Result = BaseResult[:metrics]

        STRATEGY_CLASSES = [
          DedupStrategies::ArgMaxStrategy,
          DedupStrategies::ArgMaxTupleStrategy,
          DedupStrategies::RowNumberStrategy,
          DedupStrategies::TwoPassStrategy
        ].freeze

        ALLOWED_SUM_COLUMNS = %w[decimal_value precise_total_amount_cents].freeze

        def initialize(
          subscription:,
          boundaries:,
          code:,
          sum_column: "decimal_value",
          post_dedup_where: nil,
          repetitions: 5,
          output_csv: nil,
          cold_run: false
        )
          @subscription = subscription
          @boundaries = boundaries
          @code = code
          @sum_column = sum_column
          @post_dedup_where = post_dedup_where
          @repetitions = repetitions
          @output_csv = output_csv
          @cold_run = cold_run
          super
        end

        def call
          validate_sum_column!

          strategies = STRATEGY_CLASSES.map do |klass|
            klass.new(subscription: subscription, boundaries: boundaries, code: code)
          end

          verify_equivalent_results!(strategies)

          print_header
          queries = strategies.each_with_object({}) { |s, h| h[s.name] = aggregated_sql(s) }
          metrics = Utils::ClickhouseBenchmark.compare(
            queries,
            repetitions: repetitions,
            cold_run: cold_run
          )

          write_csv(metrics) if output_csv

          result.metrics = metrics
          result
        end

        private

        attr_reader :subscription, :boundaries, :code, :sum_column, :post_dedup_where,
          :repetitions, :output_csv, :cold_run

        def validate_sum_column!
          return if ALLOWED_SUM_COLUMNS.include?(sum_column)

          raise ArgumentError,
            "sum_column must be one of #{ALLOWED_SUM_COLUMNS.inspect}, got #{sum_column.inspect}"
        end

        def aggregated_sql(strategy)
          events_select = "SELECT * FROM events_enriched"
          events_select += " WHERE #{post_dedup_where}" if post_dedup_where.present?

          ctes = {
            "events_enriched" => strategy.sql,
            "events" => events_select
          }

          with_ctes(ctes, "SELECT COALESCE(SUM(events.#{sum_column}), 0) AS agg FROM events")
        end

        def verify_equivalent_results!(strategies)
          reference = nil
          reference_name = nil

          strategies.each do |strategy|
            value = fetch_aggregate(strategy)

            if reference.nil?
              reference = value
              reference_name = strategy.name
              next
            end

            next if aggregates_equal?(value, reference)

            raise "Correctness check failed: #{strategy.name}=#{value.inspect} " \
              "diverges from #{reference_name}=#{reference.inspect}."
          end
        end

        def fetch_aggregate(strategy)
          Utils::ClickhouseConnection.connection_with_retry do |connection|
            connection.select_value(aggregated_sql(strategy))
          end
        end

        def aggregates_equal?(left, right)
          return true if left == right

          BigDecimal(left.to_s) == BigDecimal(right.to_s)
        rescue ArgumentError, TypeError
          false
        end

        # rubocop:disable Rails/Output
        def print_header
          puts ""
          puts "Subscription: #{subscription.id}   Code: #{code}   " \
               "Window: #{from_datetime}..#{to_datetime}"
          where_suffix = post_dedup_where.present? ? "  WHERE #{post_dedup_where}" : ""
          puts "Aggregate: SUM(events.#{sum_column})#{where_suffix}"
        end
        # rubocop:enable Rails/Output

        def write_csv(metrics)
          require "csv"
          CSV.open(output_csv, "w") do |csv|
            csv << %w[approach server_ms_median wall_ms_median memory_usage_median read_rows read_bytes]
            metrics.each do |name, m|
              csv << [
                name,
                m[:duration_ms_median],
                m[:wall_ms_median],
                m[:memory_usage_median],
                m[:read_rows],
                m[:read_bytes]
              ]
            end
          end
          puts "Wrote CSV: #{output_csv}" # rubocop:disable Rails/Output
        end

        def from_datetime
          boundaries[:from_datetime]
        end

        def to_datetime
          boundaries[:to_datetime]
        end
      end
    end
  end
end
