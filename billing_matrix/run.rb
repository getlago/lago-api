# frozen_string_literal: true

# Entrypoint for the billing matrix. See billing_matrix/runner/CONTRACT.md.
#
#   docker compose -f docker-compose.dev.yml exec -w /app/.worktrees/billing-matrix \
#     -e RAILS_ENV=test \
#     -e DATABASE_TEST_URL=postgresql://lago:changeme@db:5432/lago_matrix_test \
#     api bundle exec ruby billing_matrix/run.rb [options]
#
# Exit codes are the contract with CI: 0 means the suite ran and its assertion
# mechanisms are intact, whatever the rows said. Only 2 and 3 mean "do not trust
# this run".

require "optparse"
require "json"
require "benchmark"

require_relative "runner/boot"
require_relative "runner/context"
require_relative "runner/row"
require_relative "runner/world"
require_relative "runner/timeline"
require_relative "runner/observe"
require_relative "runner/comparison"
require_relative "runner/results"

module BillingMatrix
  class CLI
    DEFAULT_ROWS = %w[billing_matrix/rows billing_matrix/canaries].freeze

    EXIT_OK = 0
    EXIT_CANARY_BROKEN = 2
    EXIT_HARNESS_BROKEN = 3

    def self.call(argv)
      new(parse(argv)).call
    end

    def self.parse(argv)
      options = {
        rows: [],
        ids: [],
        areas: [],
        shard: nil,
        out: "tmp/billing_matrix/results.json"
      }

      OptionParser.new do |o|
        o.banner = "usage: ruby billing_matrix/run.rb [options]"
        o.on("--rows PATH", "directory or file of rows (repeatable)") { options[:rows] << _1 }
        o.on("--id ID", "run only this row id (repeatable)") { options[:ids] << _1 }
        o.on("--area AREA", "run only this area (repeatable)") { options[:areas] << _1 }
        o.on("--shard N/TOTAL", "run shard N of TOTAL, round-robin") { options[:shard] = _1 }
        o.on("--out PATH", "where to write results.json") { options[:out] = _1 }
        o.on("-h", "--help") { puts o; exit EXIT_OK }
      end.parse!(argv)

      options[:rows] = DEFAULT_ROWS if options[:rows].empty?
      options
    end

    def initialize(options)
      @options = options
    end

    def call
      BillingMatrix.boot!
      assert_shard_isolation!
      rows = select(load_rows)
      abort_harness("no rows matched") if rows.empty?

      results = Results.new
      rows.each do |row|
        recorded = execute(row)
        results.record(**recorded)
        log(row, results.verdict_for(row.id), recorded[:duration_ms])
      end
      results.write!(@options[:out])

      report(results, rows.size)
      results.summary[:canaries_broken].zero? ? EXIT_OK : EXIT_CANARY_BROKEN
    rescue Error, Errno::ENOENT => e
      abort_harness(e.message)
    end

    private

    # Shards must not share a database. Teardown uses the deletion strategy, which takes
    # exclusive locks across all 143 tables and deletes rows belonging to whatever else is
    # running — two shards on one database silently corrupt each other's worlds rather than
    # failing. Requiring the database name to carry the shard index makes separate databases
    # structurally necessary instead of merely documented.
    def assert_shard_isolation!
      return unless @options[:shard]

      index = @options[:shard].split("/").first
      database = ActiveRecord::Base.connection_db_config.database.to_s
      return if database.end_with?("_#{index}_test")

      raise Error, "refusing to run shard #{@options[:shard]} against #{database.inspect}: " \
                   "each shard needs its own database, named …_#{index}_test — the index sits " \
                   "before the suffix so the name still ends in _test, which boot! requires. " \
                   "Point DATABASE_TEST_URL at it, or drop --shard and run the rows in one process."
    end

    # Cross-corpus checks run over every directory at once. A single load_all cannot
    # see the whole corpus, so duplicate ids and dangling control: references are only
    # detectable here.
    def load_rows
      rows = @options[:rows].flat_map { Row.load_all(_1) }
      Row.reject_duplicate_ids!(rows)
      Row.check_controls!(rows)
      rows
    end

    def select(rows)
      rows = rows.select { @options[:ids].include?(_1.id) } if @options[:ids].any?
      rows = rows.select { @options[:areas].include?(_1.area) } if @options[:areas].any?
      return rows unless @options[:shard]

      index, total = @options[:shard].split("/").map(&:to_i)
      rows.each_with_index.filter_map { |row, i| row if (i % total) == (index - 1) }
    end

    # One row, one fully isolated world. Anything the row does that the harness
    # cannot do is :errored — never :passed, because an unrun row that reports
    # green is the failure mode this whole suite exists to avoid. Canary rows are
    # not special-cased here; Results owns that flip so it happens exactly once.
    def execute(row)
      mismatches = []
      error = nil
      verdict = nil

      elapsed = Benchmark.realtime do
        Context.isolate do |ctx|
          World.build!(ctx, row.setup)
          Timeline.run!(ctx, row.timeline)
          comparison = Comparison.call(expected: row.expect, observed: Observe.call(ctx, row.expect))
          mismatches = comparison.mismatches
          verdict = comparison.match? ? :passed : :failed
        end
      rescue Unsupported, StandardError => e
        error = "#{e.class}: #{e.message}"
        verdict = :errored
      end

      {row:, verdict:, mismatches:, error:, duration_ms: (elapsed * 1000).round}
    end

    # Verdicts are logged as Results recorded them, after canary semantics have been
    # applied there. A canary that correctly failed reads "ok"; one that passed reads
    # "VOID", because it has stopped asserting anything.
    def log(row, verdict, duration_ms)
      mark = {passed: "ok  ", failed: "FAIL", errored: "ERR ", canary_broken: "VOID"}.fetch(verdict)
      warn format("%s %6.1fs  %s", mark, duration_ms / 1000.0, row.id)
    end

    def report(results, count)
      s = results.summary
      warn ""
      warn "#{count} rows  ·  #{s[:passed]} passed  ·  #{s[:failed]} failed  ·  #{s[:errored]} errored"
      warn "results: #{@options[:out]}"
      return if s[:canaries_broken].zero?

      warn ""
      warn "#{s[:canaries_broken]} canary/canaries PASSED, which means they no longer assert anything."
      warn "This run proves nothing. Fix the assertion mechanism before trusting any result above."
    end

    def abort_harness(message)
      warn "billing matrix could not run: #{message}"
      EXIT_HARNESS_BROKEN
    end
  end
end

exit BillingMatrix::CLI.call(ARGV) if $PROGRAM_NAME == __FILE__
