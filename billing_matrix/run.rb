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
        o.on("--rows PATH", "directory or file of rows (repeatable)") { options[:rows] << it }
        o.on("--id ID", "run only this row id (repeatable)") { options[:ids] << it }
        o.on("--area AREA", "run only this area (repeatable)") { options[:areas] << it }
        o.on("--shard N/TOTAL", "run shard N of TOTAL, round-robin") { options[:shard] = it }
        o.on("--out PATH", "where to write results.json") { options[:out] = it }
        o.on("-h", "--help") {
          puts o
          exit EXIT_OK
        }
      end.parse!(argv)

      options[:rows] = DEFAULT_ROWS if options[:rows].empty?
      options
    end

    def initialize(options)
      @options = options
    end

    def call
      rows = select(load_rows)
      raise Error, "no rows matched" if rows.empty?

      BillingMatrix.boot!(shard: @options[:shard])
      # Importing CLI for unit tests must not boot the scenario context or clean the database.
      require_relative "runner/context"

      results = Results.new
      rows.each do |row|
        recorded = execute(row)
        results.record(**recorded)
        log(row, results.verdict_for(row.id), recorded[:duration_ms])
      end
      results.write!(@options[:out])

      report(results, rows.size)
      trustworthy_exit(results, rows)
    rescue Error, Errno::ENOENT => e
      abort_harness(e.message)
    end

    private

    def load_rows
      Row.load_all(@options[:rows])
    end

    def select(rows)
      rows = rows.select { @options[:ids].include?(it.id) } if @options[:ids].any?
      rows = rows.select { @options[:areas].include?(it.area) } if @options[:areas].any?
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

    # A canary that did not fail is a canary that asserted nothing, whether it passed or
    # blew up on the way. Both make the run unusable, so both exit 2. Selecting a subset of
    # rows by hand legitimately runs no canaries at all — that is a debugging run, and it
    # says so rather than claiming a verdict it cannot support.
    def trustworthy_exit(results, rows)
      return EXIT_OK if results.trustworthy?

      if results.summary[:canaries_total].zero?
        warn ""
        warn "No canaries ran, so nothing here is vouched for. Run the full corpus before " \
             "treating any of this as a result."
        return rows.any?(&:canary) ? EXIT_CANARY_BROKEN : EXIT_OK
      end

      EXIT_CANARY_BROKEN
    end

    def report(results, count)
      s = results.summary
      warn ""
      warn "#{count} rows  ·  #{s[:passed]} passed  ·  #{s[:failed]} failed  ·  #{s[:errored]} errored"
      warn "results: #{@options[:out]}"
      return if s[:canaries_unproven].zero?

      warn ""
      if s[:canaries_broken].positive?
        warn "#{s[:canaries_broken]} canary/canaries PASSED, which means they no longer assert anything."
      end
      errored_canaries = s[:canaries_unproven] - s[:canaries_broken]
      if errored_canaries.positive?
        warn "#{errored_canaries} canary/canaries never got as far as asserting anything."
      end
      warn "This run proves nothing. Fix the assertion mechanism before trusting any result above."
    end

    def abort_harness(message)
      warn "billing matrix could not run: #{message}"
      EXIT_HARNESS_BROKEN
    end
  end
end

exit BillingMatrix::CLI.call(ARGV) if $PROGRAM_NAME == __FILE__
