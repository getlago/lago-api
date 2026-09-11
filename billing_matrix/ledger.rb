# frozen_string_literal: true

# Turns a run's results.json into the day's news.
#
#   ruby billing_matrix/ledger.rb --results tmp/billing_matrix/results.json
#   ruby billing_matrix/ledger.rb --apply --format slack
#
# Pure Ruby: no Rails, no database. It reads two files and decides what a person
# needs to be told. Reporting a state rather than a transition is how a daily report
# becomes something people scroll past, so only transitions are ever emitted.

require "yaml"
require "json"
require "date"
require "optparse"

module BillingMatrix
  class Ledger
    EXIT_OK = 0
    EXIT_VOID = 2
    EXIT_BROKEN = 3

    # A row that errored tells us the harness could not run it. That is not evidence
    # about Lago's billing either way, so it never moves a ledger entry — it is
    # reported on its own so it cannot be mistaken for coverage.
    def self.call(argv)
      options = parse(argv)
      new(
        results: JSON.parse(File.read(options[:results])),
        entries: YAML.safe_load_file(options[:ledger], permitted_classes: [Date]) || [],
        # Time.zone.today needs ActiveSupport, and this file loads no Rails.
        today: options[:today] ? Date.parse(options[:today]) : Date.today # rubocop:disable Rails/Date
      ).run(options)
    rescue Errno::ENOENT, JSON::ParserError, Psych::SyntaxError => e
      warn "ledger: #{e.message}"
      EXIT_BROKEN
    end

    def self.parse(argv)
      options = {
        results: "tmp/billing_matrix/results.json",
        ledger: "billing_matrix/ledger.yml",
        format: "text",
        apply: false,
        pr_url: nil,
        today: nil
      }
      OptionParser.new do |o|
        o.on("--results PATH") { options[:results] = it }
        o.on("--ledger PATH") { options[:ledger] = it }
        o.on("--format FMT", %w[text slack]) { options[:format] = it }
        o.on("--apply", "rewrite the ledger in place") { options[:apply] = true }
        o.on("--pr-url URL", "link included in the report") { options[:pr_url] = it }
        o.on("--today DATE", "override today, for testing") { options[:today] = it }
        o.on("-h", "--help") {
          puts o
          exit EXIT_OK
        }
      end.parse!(argv)
      options
    end

    def initialize(results:, entries:, today:)
      @results = results
      @entries = entries.map { |e| stringify(e.transform_keys(&:to_s)) }
      @today = today
      # Dates are written as ISO strings, never as Date objects: Psych emits a YAML
      # anchor for every repeated object, so a shared Date turns the file into
      # `first_seen: *1` — still valid, but unreadable in the pull request that is the
      # whole reason the ledger is reviewed by a person.
      @stamp = today.to_s
    end

    def run(options)
      return void_run if void?

      diff = compute
      write!(options[:ledger], diff[:entries]) if options[:apply]
      puts render(diff, options)
      EXIT_OK
    end

    # Any canary that did not fail — it passed, or it errored before asserting — means an
    # assertion mechanism went unexercised, so every verdict in the file was produced by
    # machinery we can no longer vouch for: the ledger must not move and the report must not
    # pretend to be news. A results file with no canaries at all is a hand-filtered debugging
    # run, and must not move the ledger either.
    def void?
      summary.fetch("canaries_unproven", 0).positive? ||
        summary.fetch("canaries_total", 0).zero? ||
        summary.fetch("canaries_broken", 0).positive?
    end

    def void_run
      reason =
        if summary.fetch("canaries_total", 0).zero?
          "this run contains no canaries, so none of its verdicts are vouched for"
        else
          "#{summary["canaries_unproven"]} of #{summary["canaries_total"]} canaries did not " \
            "fail as designed, so this run's verdicts prove nothing"
        end
      warn "ledger: refusing to apply — #{reason}. Fix the assertion mechanism and re-run."
      EXIT_VOID
    end

    private

    def summary
      @results.dig("run", "summary") || {}
    end

    # Canaries are about the harness, not about billing, so they are not ledger material.
    def rows
      @results.fetch("rows", []).reject { it["area"] == "canary" }
    end

    def compute
      # index_by is ActiveSupport, and this file loads no Rails — see the header.
      by_id = @entries.to_h { [it["id"], it] } # rubocop:disable Rails/IndexBy
      newly_failed = []
      fixed = []
      still_failing = []
      returned = []
      kept = []

      rows.each do |row|
        entry = by_id.delete(row["id"])
        if entry && row.key?("pins") && %w[failed passed].include?(row["verdict"])
          entry = entry.merge("pins" => row["pins"])
        end

        case [row["verdict"], entry&.fetch("status", nil)]
        in ["failed", nil]
          kept << (fresh = failed_entry(row))
          newly_failed << fresh
        in ["failed", "failed"]
          kept << entry.merge("last_seen" => @stamp)
          still_failing << entry
        in ["failed", "fixed"]
          # The same bug, come back. It keeps its original first_seen and simply
          # reappears in the failed list — there is deliberately no separate category.
          kept << entry.merge("status" => "failed", "last_seen" => @stamp).tap { it.delete("fixed_on") }
          returned << entry
        in ["passed", "failed"]
          kept << entry.merge("status" => "fixed", "fixed_on" => @stamp)
          fixed << entry
        in ["passed", "fixed"]
          # Announced yesterday, so today it is simply gone. This is the rule that stops
          # the file filling up with things nobody needs to read again.
          nil
        else
          kept << entry if entry
        end
      end

      # Entries whose row is no longer in the corpus are left untouched rather than
      # silently dropped: a row deleted while its bug is open is a decision for a person.
      # But they are also called out, because an entry no row can ever satisfy is entry
      # that can never be pruned — the pruning rule needs a row to pass twice. Left
      # unreported, a mistyped or renamed id becomes permanent dead weight in a file whose
      # whole value is that everything in it is still true.
      warn_about_orphans(by_id.values)
      kept.concat(by_id.values)

      {
        entries: kept.sort_by { it["id"] },
        newly_failed: newly_failed,
        fixed: fixed,
        returned: returned,
        still_failing: still_failing,
        errored: rows.select { it["verdict"] == "errored" }
      }
    end

    # Goes to stderr, so it lands in the workflow log for whoever is looking rather than
    # into the Slack report — it is a maintenance signal, not billing news. A sharded run
    # legitimately sees only its own slice, hence the caveat.
    def warn_about_orphans(orphans)
      return if orphans.empty?

      warn "ledger: #{orphans.size} entr#{(orphans.size == 1) ? "y" : "ies"} matched no row in " \
           "this run and cannot be pruned. Either the row was renamed or deleted, or the id " \
           "never matched one. Move it to leads.yml if no row covers it yet. " \
           "(Expected when running a single shard.)"
      orphans.first(10).each { warn "  - #{it["id"]}" }
    end

    def failed_entry(row)
      {
        "id" => row["id"],
        "pins" => row["pins"],
        "status" => "failed",
        "first_seen" => @stamp,
        "last_seen" => @stamp,
        "note" => first_mismatch(row)
      }.compact
    end

    # YAML gives back a Date for an unquoted date; everything downstream compares and
    # writes ISO strings, which sort identically and round-trip without anchors.
    def stringify(entry)
      entry.transform_values { it.is_a?(Date) ? it.to_s : it }
    end

    def first_mismatch(row)
      m = row["mismatches"]&.first
      return row["error"] unless m

      "#{m["path"]}: expected #{m["expected"].inspect}, got #{m["observed"].inspect}"
    end

    def write!(path, entries)
      File.write(path, <<~HEAD + (entries.empty? ? "[]\n" : YAML.dump(entries).delete_prefix("---\n")))
        # What the billing matrix knows is broken, and since when.
        #
        # Maintained by .github/workflows/billing-matrix-daily.yml, which proposes every
        # change as a pull request rather than committing here directly. Two statuses only:
        # a row that fails is `failed`; a row that starts passing is `fixed` for exactly one
        # run and is then removed. A bug that comes back keeps its original first_seen.
      HEAD
    end

    def news?(diff)
      [diff[:newly_failed], diff[:fixed], diff[:returned], diff[:errored]].any?(&:any?)
    end

    def render(diff, options)
      return "" unless news?(diff)

      ((options[:format] == "slack") ? slack(diff, options) : text(diff)).strip
    end

    def text(diff)
      lines = ["billing matrix · #{@today.strftime("%-d %b %Y")}", ""]
      section(lines, "newly failing", diff[:newly_failed]) { "#{it["id"]}#{finding_suffix(it)}\n      #{it["note"]}" }
      section(lines, "failing again", diff[:returned]) { "#{it["id"]}#{finding_suffix(it)} (first seen #{it["first_seen"]})" }
      section(lines, "fixed", diff[:fixed]) { "#{it["id"]}#{finding_suffix(it)} (failed since #{it["first_seen"]})" }
      section(lines, "errored", diff[:errored]) { "#{it["id"]}#{finding_suffix(it)}\n      #{it["error"]}" }
      unless diff[:still_failing].empty?
        oldest = diff[:still_failing].map { it["first_seen"] }.min
        lines << "#{diff[:still_failing].size} still failing, not reported again (oldest #{oldest})"
      end
      lines << ""
      lines << counts
      lines.join("\n")
    end

    def finding_suffix(entry)
      pins = entry.fetch("pins", [])
      pins.empty? ? "" : " (#{pins.join(", ")})"
    end

    def section(lines, label, items)
      return if items.empty?

      lines << "#{label} (#{items.size})"
      items.each { lines << "    #{yield(it)}" }
      lines << ""
    end

    def slack(diff, options)
      parts = ["*Billing matrix* · #{@today.strftime("%-d %b %Y")}"]
      parts << bullets(":red_circle: *#{diff[:newly_failed].size} newly failing*", diff[:newly_failed]) { "`#{it["id"]}`#{finding_suffix(it)}\n   #{it["note"]}" }
      parts << bullets(":arrows_counterclockwise: *#{diff[:returned].size} failing again*", diff[:returned]) { "`#{it["id"]}`#{finding_suffix(it)} — first seen #{it["first_seen"]}" }
      parts << bullets(":white_check_mark: *#{diff[:fixed].size} fixed*", diff[:fixed]) { "`#{it["id"]}`#{finding_suffix(it)} — had failed since #{it["first_seen"]}" }
      parts << bullets(":warning: *#{diff[:errored].size} errored*", diff[:errored]) { "`#{it["id"]}`#{finding_suffix(it)}\n   #{it["error"]}" }
      unless diff[:still_failing].empty?
        parts << "_#{diff[:still_failing].size} still failing, already reported (oldest #{diff[:still_failing].map { it["first_seen"] }.min})_"
      end
      parts << counts
      parts << "Ledger PR: #{options[:pr_url]}" if options[:pr_url]
      parts.compact.join("\n\n")
    end

    def bullets(heading, items)
      return nil if items.empty?

      ([heading] + items.map { "• #{yield(it)}" }).join("\n")
    end

    # Counted over the same rows the report is about — canaries excluded. Taking these
    # from run.summary instead mixes a canary-excluded row count with canary-inclusive
    # tallies, and prints nonsense like "9 rows · 10 passed".
    def counts
      tally = rows.group_by { it["verdict"] }.transform_values(&:size)
      "#{rows.size} rows · #{tally.fetch("passed", 0)} passed · " \
        "#{tally.fetch("failed", 0)} failed · #{tally.fetch("errored", 0)} errored"
    end
  end
end

exit BillingMatrix::Ledger.call(ARGV) if $PROGRAM_NAME == __FILE__
