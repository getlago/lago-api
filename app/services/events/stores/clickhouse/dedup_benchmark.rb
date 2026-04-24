# frozen_string_literal: true

require "benchmark"
require "securerandom"

module Events
  module Stores
    module Clickhouse
      # Console-only harness. Compares the current argMax GROUP BY deduplication
      # against three alternatives against whatever data lives in the connected
      # ClickHouse. Does NOT seed data and does NOT drop caches (both unsafe in prod).
      #
      # Each strategy's SQL is wrapped in the same CTE shape production uses
      # (see ClickhouseStore#events_cte_queries_with_deduplication):
      #
      #   WITH events_enriched AS (<strategy dedup sql>),
      #        events         AS (SELECT * FROM events_enriched [WHERE <post_dedup_where>])
      #   SELECT COALESCE(SUM(events.<sum_column>), 0) FROM events
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
          @run_id = SecureRandom.uuid
          super
        end

        def call
          validate_sum_column!

          strategies = STRATEGY_CLASSES.map do |klass|
            klass.new(subscription: subscription, boundaries: boundaries, code: code)
          end

          verify_equivalent_results!(strategies)

          wall_times = execute_repetitions(strategies)
          flush_query_log
          server_rows = fetch_query_log_rows

          metrics = build_metrics(strategies, wall_times, server_rows)
          print_table(metrics)
          write_csv(metrics) if output_csv

          result.metrics = metrics
          result
        end

        private

        attr_reader :subscription, :boundaries, :code, :sum_column, :post_dedup_where,
          :repetitions, :output_csv, :cold_run, :run_id

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

        def execute_repetitions(strategies)
          wall = strategies.each_with_object({}) { |s, h| h[s.name] = [] }

          repetitions.times do |rep_idx|
            strategies.shuffle.each do |strategy|
              tag = tag_for(strategy, rep_idx)
              tagged_sql = with_settings(aggregated_sql(strategy), tag)

              elapsed = Benchmark.realtime do
                Utils::ClickhouseConnection.connection_with_retry do |connection|
                  connection.select_value(tagged_sql)
                end
              end

              wall[strategy.name] << (elapsed * 1000).to_i
            end
          end

          wall
        end

        def with_settings(sql, tag)
          settings = ["log_comment = #{ActiveRecord::Base.connection.quote(tag)}"]
          settings << "use_uncompressed_cache = 0" if cold_run
          "#{sql} SETTINGS #{settings.join(", ")}"
        end

        def tag_for(strategy, rep_idx)
          "dedup_bench_#{run_id}_#{strategy_key(strategy)}_#{rep_idx}"
        end

        def strategy_key(strategy)
          strategy.class.name.demodulize.underscore
        end

        def flush_query_log
          Utils::ClickhouseConnection.connection_with_retry do |connection|
            connection.execute("SYSTEM FLUSH LOGS")
          end
        rescue => e
          warn "SYSTEM FLUSH LOGS failed (#{e.class}: #{e.message}); falling back to sleep."
          sleep 8
        end

        def fetch_query_log_rows
          sql = ActiveRecord::Base.sanitize_sql_for_conditions(
            [
              "SELECT log_comment, query_duration_ms, memory_usage, read_rows, read_bytes, result_rows " \
              "FROM system.query_log " \
              "WHERE type = 'QueryFinish' AND log_comment LIKE ?",
              "dedup_bench_#{run_id}_%"
            ]
          )

          Utils::ClickhouseConnection.connection_with_retry do |connection|
            connection.select_all(sql).to_a
          end
        rescue => e
          warn "Could not read system.query_log (#{e.class}: #{e.message}); server metrics unavailable."
          []
        end

        def build_metrics(strategies, wall_times, server_rows)
          grouped = server_rows.group_by { |r| parse_strategy_key(r["log_comment"]) }

          strategies.each_with_object({}) do |strategy, out|
            key = strategy_key(strategy)
            runs = grouped[key] || []

            out[strategy.name] = {
              wall_ms_median: median(wall_times[strategy.name]),
              duration_ms_median: median(runs.map { |r| r["query_duration_ms"].to_i }),
              memory_usage_median: median(runs.map { |r| r["memory_usage"].to_i }),
              read_rows: runs.first&.dig("read_rows").to_i,
              read_bytes: runs.first&.dig("read_bytes").to_i,
              result_rows: runs.first&.dig("result_rows").to_i,
              wall_ms_runs: wall_times[strategy.name],
              server_runs: runs
            }
          end
        end

        def parse_strategy_key(log_comment)
          # format: dedup_bench_<run_id>_<strategy_key>_<rep_idx>
          return nil if log_comment.nil?

          match = log_comment.match(/\Adedup_bench_#{run_id}_(.+)_\d+\z/)
          match && match[1]
        end

        def median(values)
          return 0 if values.blank?

          sorted = values.sort
          mid = sorted.size / 2
          if sorted.size.odd?
            sorted[mid]
          else
            (sorted[mid - 1] + sorted[mid]) / 2
          end
        end

        # rubocop:disable Rails/Output
        def print_table(metrics)
          puts ""
          puts "Subscription: #{subscription.id}   Code: #{code}   " \
               "Window: #{from_datetime}..#{to_datetime}"
          where_suffix = post_dedup_where.present? ? "  WHERE #{post_dedup_where}" : ""
          puts "Aggregate: SUM(events.#{sum_column})#{where_suffix}"
          cold_suffix = cold_run ? "  [cold: use_uncompressed_cache=0]" : ""
          puts "Repetitions: #{repetitions} (median reported)#{cold_suffix}"
          puts ""

          header = "Approach           |  Server ms |    Wall ms |     Peak mem |    Rows read |   Bytes read"
          puts header
          puts "-" * header.length

          metrics.each do |name, m|
            puts format(
              "%-18s | %10d | %10d | %12s | %12s | %12s",
              name,
              m[:duration_ms_median],
              m[:wall_ms_median],
              format_bytes(m[:memory_usage_median]),
              format_number(m[:read_rows]),
              format_bytes(m[:read_bytes])
            )
          end
          puts ""
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

        def format_bytes(bytes)
          bytes = bytes.to_i
          return "0 B" if bytes.zero?

          units = %w[B KiB MiB GiB TiB]
          exp = (Math.log(bytes) / Math.log(1024)).floor
          exp = [exp, units.size - 1].min
          format("%.1f %s", bytes.to_f / (1024**exp), units[exp])
        end

        def format_number(n)
          n.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
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
