# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

require_relative "errors"

module BillingMatrix
  # Collects one verdict per row and writes the run's results.json.
  #
  # `record` takes the verdict the caller would give the row if it were an ordinary row —
  # :passed or :failed from a Comparison result, :errored from a raised exception — and applies
  # canary semantics itself:
  #
  #   ordinary row, matched      -> :passed
  #   ordinary row, mismatched   -> :failed
  #   canary row,   matched      -> :canary_broken   (the row was built to fail; it didn't, so
  #                                                    the assertion mechanism it guards is broken)
  #   canary row,   mismatched   -> :passed           (the mechanism caught the planted defect)
  #   any row,      errored      -> :errored          (unchanged — an error proves nothing about
  #                                                    whether the mechanism works)
  #
  # Centralizing the flip here means it is applied exactly once, in one place, regardless of what
  # calls record — the old suite lost a canary guard for weeks to an ensure/throw bug that skipped
  # this exact check.
  class Results
    VERDICTS = %i[passed failed errored canary_broken].freeze

    Row = Struct.new(:id, :area, :canary, :verdict, :duration_ms, :mismatches, :error, keyword_init: true)

    def initialize
      @rows = []
      @started_at = Time.now.utc
    end

    def record(row:, verdict:, mismatches: [], error: nil, duration_ms:)
      raise ArgumentError, "unknown verdict #{verdict.inspect}" unless VERDICTS.include?(verdict)

      @rows << Row.new(
        id: row.id,
        area: row.area,
        canary: !row.canary.nil?,
        verdict: apply_canary_semantics(row, verdict),
        duration_ms: duration_ms,
        mismatches: mismatches,
        error: error
      )
    end

    # The verdict as recorded, i.e. after canary semantics. The entrypoint logs this
    # rather than the raw comparison outcome, so a healthy canary does not print as a
    # failure.
    def verdict_for(id)
      @rows.find { |row| row.id == id }&.verdict
    end

    # A canary is proven only by failing its assertion, which records as :passed here.
    # Anything else — it errored, or it passed and got flipped to :canary_broken — means
    # the mechanism it guards was never exercised this run.
    #
    # Counting only :canary_broken was not enough: a run against an unmigrated database
    # errored every row, left canaries_broken at zero, and reported a green build. A run
    # in which no canary actually failed proves nothing, however the canaries got there.
    def summary
      {
        passed: count(:passed),
        failed: count(:failed),
        errored: count(:errored),
        canaries_broken: count(:canary_broken),
        canaries_total: canaries.size,
        canaries_unproven: canaries.count { _1.verdict != :passed }
      }
    end

    def canaries
      @rows.select(&:canary)
    end

    # The single question the rest of the pipeline asks: may today's verdicts be believed?
    def trustworthy?
      canaries.any? && summary[:canaries_unproven].zero?
    end

    def write!(path)
      payload = to_h
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(payload))
      payload
    end

    def to_h
      {
        run: {
          started_at: @started_at.iso8601,
          finished_at: Time.now.utc.iso8601,
          revision: git_revision,
          summary: summary
        },
        rows: @rows.map { |row| row_to_h(row) }
      }
    end

    private

    def apply_canary_semantics(row, verdict)
      return verdict unless row.canary

      case verdict
      when :passed then :canary_broken
      when :failed then :passed
      else verdict
      end
    end

    def count(verdict)
      @rows.count { |row| row.verdict == verdict }
    end

    def row_to_h(row)
      {
        id: row.id,
        area: row.area,
        verdict: row.verdict.to_s,
        duration_ms: row.duration_ms,
        mismatches: row.mismatches,
        error: row.error
      }
    end

    # `git rev-parse` cannot resolve anything inside the api container: `.git` there is a
    # submodule gitlink pointing at .../lago/.git/modules/api, which lives outside the mounted
    # volume and is invisible from inside the container. An env var, if the caller sets one, is
    # the only reliable source in that environment; a real .git is a bonus for other contexts.
    def git_revision
      env_revision = ENV["GIT_SHA"] || ENV["GITHUB_SHA"] || ENV["CI_COMMIT_SHA"]
      return env_revision unless env_revision.nil? || env_revision.empty?

      sha = `git rev-parse HEAD 2>/dev/null`.strip
      sha.empty? ? nil : sha
    rescue
      nil
    end
  end
end
