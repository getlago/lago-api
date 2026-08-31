# frozen_string_literal: true

# Ledger and documentation tasks for the golden billing suite.
#
#   bundle exec rake golden:ledger    # print coverage, gaps and risk
#   bundle exec rake golden:docs      # regenerate spec/scenarios/golden/COVERAGE.md
#
# The suite itself runs through RSpec (spec/scenarios/golden); these tasks only measure and report.
namespace :golden do
  def load_golden_support
    %w[golden_comparison golden_matrix golden_legality golden_capabilities golden_ledger golden_surface golden_findings].each do |file|
      require Rails.root.join("spec/support/#{file}")
    end
  end

  # Fix-commit density per block, read from a committed bugmap rather than computed here: `api` is a
  # git submodule whose real .git directory is not mounted into the container, so git cannot run where
  # this task runs. Regenerate on the host with `ruby dev/golden/bugmap.rb`.
  def fix_counts(blocks)
    path = GoldenMatrix.dir.join("bugmap.json")
    return blocks.to_h { |block| [block[:id], nil] } unless path.exist?

    counts = JSON.parse(File.read(path)).fetch("blocks", {})
    blocks.to_h { |block| [block[:id], counts[block[:id]]] }
  end

  def ledger_rows
    summary = GoldenLedger.summary
    fixes = fix_counts(summary)

    summary.map do |block|
      uncovered = block[:legal] - block[:covered]
      count = fixes[block[:id]]
      # RISK = fixes × the fraction of the block still blind, i.e. expected unguarded bug density,
      # decaying to 0 as a block approaches full coverage. Not fixes-per-uncovered-cell, which
      # penalises large blocks. Blindness is measured against EXPRESSIBLE cells, not legal ones, so
      # the ranking never points at work nobody can do.
      uncovered_expressible = block[:expressible] - block[:covered]
      blindness = block[:expressible].zero? ? 0 : uncovered_expressible.to_f / block[:expressible]
      block.merge(
        uncovered: uncovered,
        uncovered_expressible: uncovered_expressible,
        fixes: count,
        risk: count ? (count * blindness).round(1) : nil
      )
    end
  end

  desc "Print the golden billing coverage ledger"
  task ledger: :environment do
    load_golden_support
    rows = ledger_rows
    totals = GoldenLedger.totals
    actions = GoldenLedger.action_summary

    puts "BLOCK TITLE                             ROWS  CELLS  WRITEABLE  COVER      %  BLOCKED  FIXES   RISK"
    puts "-" * 100
    rows.sort_by { |row| -(row[:risk] || 0) }.each do |row|
      puts format(
        "%-5s %-31s %6d %6d %10d %6d %5d%% %8d %6s %6s",
        row[:id], row[:title].to_s[0, 31], row[:rows], row[:legal], row[:expressible], row[:covered],
        row[:expressible_percent], row[:blocked], row[:fixes] || "—", row[:risk] || "—"
      )
    end
    puts "-" * 100
    puts format("%-37s %6d %6d %10d %6d %5d%% %8d",
      "TOTAL", totals[:rows], totals[:legal], totals[:expressible], totals[:covered],
      totals[:expressible_percent], totals[:blocked])
    puts
    puts "WRITEABLE is what the harness can express today; % is of that, not of CELLS. BLOCKED cells"
    puts "need a harness capability first and are listed below — they are work, not a permanent hole."
    puts
    puts "Actions: #{actions[:covered]}/#{actions[:total]} (#{actions[:percent]}%) in scope; " \
         "#{actions[:out_of_scope]} mutating routes deliberately out of scope"
    unreachable = rows.sum { |row| row[:api_unreachable] }
    if unreachable.positive?
      per_block = rows.reject { |row| row[:api_unreachable].zero? }.map { |row| "#{row[:id]} #{row[:api_unreachable]}" }
      puts "Excluded: #{unreachable} model-legal cell(s) the REST API cannot express (#{per_block.join(", ")})"
    end

    problems = rows.flat_map { |row| row[:illegal].map { |cell| "#{row[:id]} claims illegal cell #{cell.inspect}" } } +
      rows.flat_map { |row| row[:malformed].map { |m| "#{m[:id]} names axes #{m.slice(:missing, :extra).inspect}" } }

    if problems.any?
      puts
      puts "DRIFT — #{problems.size} problem(s); a validation rule may have changed under the matrix:"
      problems.each { |problem| puts "  - #{problem}" }
    end

    blocked = rows.reject { |row| row[:blocked].zero? }
    if blocked.any?
      puts
      puts "Blocked on harness capability:"
      blocked.sort_by { |row| -row[:blocked] }.each do |row|
        reasons = row[:blocked_reasons].map { |reason, count| "#{reason} (#{count})" }.join(", ")
        puts format("  %-5s %3d cell(s) — %s", row[:id], row[:blocked], reasons)
      end
    end

    puts
    # A block that has only ever read finalized invoices is blind to drafts, refreshes and previews —
    # a third of the behaviour, and where the reported production bugs live.
    blind = GoldenLedger.surface_blind_blocks
    if blind.any?
      puts
      puts "Surface-blind blocks (only ever assert a finalized invoice): #{blind.join(", ")}"
      puts "  Each needs at least one draft / regenerated / preview row. BIL-537 is what this costs:"
      puts "  B13 covered a units change 36 ways and could not see it, having never held an invoice open."
    end

    puts
    puts "Highest-risk gaps (writeable only):"
    rows.reject { |row| row[:risk].nil? }.sort_by { |row| -row[:risk] }.first(5).each do |row|
      sample = row[:missing].first(3).map { |cell| cell.values.join("/") }
      puts format("  %-5s risk %-6s %d writeable and uncovered — e.g. %s",
        row[:id], row[:risk], row[:uncovered_expressible], sample.join(", "))
    end
  end

  desc "Regenerate spec/scenarios/golden/COVERAGE.md"
  task docs: :environment do
    load_golden_support
    Rake::Task["golden:findings:export"].invoke
    rows = ledger_rows
    totals = GoldenLedger.totals
    actions = GoldenLedger.action_summary
    path = GoldenMatrix.dir.join("COVERAGE.md")

    out = []
    out << "# Golden billing suite — coverage"
    out << ""
    out << "> Generated by `bundle exec rake golden:docs`. Do not edit by hand."
    out << ""
    out << "**#{totals[:covered]} of #{totals[:expressible]} writeable cells covered " \
           "(#{totals[:expressible_percent]}%)** across #{totals[:blocks]} blocks, from #{totals[:rows]} rows. " \
           "Actions: **#{actions[:covered]}/#{actions[:total]} (#{actions[:percent]}%)**."
    out << ""
    out << "A further **#{totals[:blocked]} of #{totals[:legal]} legal cells cannot be written yet** — they need a"
    out << "harness capability first. They are listed per block below rather than subtracted silently,"
    out << "because a cell nobody can write is work, not a permanent hole in a percentage."
    out << ""
    out << "Coverage is measured per block against that block's own axis product. Legal cells are"
    out << "derived from Lago's own model constants and validators, so the denominator grows by itself"
    out << "when a charge model, aggregation or interval is added — a new capability shows up here as"
    out << "uncovered instead of silently making these percentages a lie."
    out << ""
    unreachable = rows.sum { |row| row[:api_unreachable] }
    if unreachable.positive?
      per_block = rows.reject { |row| row[:api_unreachable].zero? }.map { |row| "#{row[:id]} (#{row[:api_unreachable]})" }
      out << "**#{unreachable} model-legal cell(s) are excluded** because the REST API cannot express"
      out << "them — #{per_block.join(", ")}. They are subtracted from the denominator rather than"
      out << "counted as gaps, so the percentages mean \"of what the API can reach\"."
      out << ""
    end
    out << "`FIXES` counts `fix:`/`bug:` commits touching the block's services since 2024-01-01."
    out << "`RISK` is fixes × the fraction of the block still uncovered — expected unguarded bug"
    out << "density. It ranks what to write next by evidence rather than by taste, and decays to 0"
    out << "as a block approaches full coverage."
    out << ""
    out << "| Block | Title | Rows | Cells | Writeable | Covered | % | Blocked | Fixes | Risk |"
    out << "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"
    rows.sort_by { |row| -(row[:risk] || 0) }.each do |row|
      out << "| #{row[:id]} | #{row[:title]} | #{row[:rows]} | #{row[:legal]} | #{row[:expressible]} | " \
             "#{row[:covered]} | #{row[:expressible_percent]}% | #{row[:blocked]} | " \
             "#{row[:fixes] || "—"} | #{row[:risk] || "—"} |"
    end
    out << ""
    blocked = rows.reject { |row| row[:blocked].zero? }
    if blocked.any?
      out << "### Blocked on harness capability"
      out << ""
      out << "These cells are legal and reachable through the API, but the harness has nowhere to say"
      out << "them. Each line names what is missing — building it unblocks the count beside it."
      out << ""
      out << "| Block | Cells | Needs |"
      out << "|---|---:|---|"
      blocked.sort_by { |row| -row[:blocked] }.each do |row|
        needs = row[:blocked_reasons].map { |reason, count| "`#{reason}` (#{count})" }.join("<br>")
        out << "| #{row[:id]} | #{row[:blocked]} | #{needs} |"
      end
      out << ""
    end
    out << ""

    drift = rows.flat_map { |row| row[:illegal].map { |cell| "`#{row[:id]}` claims illegal cell `#{cell.inspect}`" } } +
      rows.flat_map { |row| row[:malformed].map { |m| "`#{m[:id]}` names axes #{m.slice(:missing, :extra).inspect}" } }
    if drift.any?
      out << "## Drift"
      out << ""
      out << "A validation rule may have changed under the matrix. Investigate before adding rows."
      out << ""
      drift.each { |item| out << "- #{item}" }
      out << ""
    end

    out << "## What each block covers, and why it exists"
    out << ""
    GoldenLedger.blocks.each do |block|
      row = rows.find { |r| r[:id] == block["id"] }
      out << "### #{block["id"]} — #{block["title"]}"
      out << ""
      out << block["why"].to_s.strip
      out << ""
      axes = block["axes"].map { |name, spec| "`#{name}` (#{GoldenLedger.axis_values(spec).size})" }
      out << "- Axes: #{axes.join(" × ")}"
      out << "- Legal cells: #{row[:legal]} · covered: #{row[:covered]} (#{row[:percent]}%)"
      if row[:missing].any?
        sample = row[:missing].first(8).map { |cell| "`#{cell.values.join("/")}`" }
        out << "- Uncovered (first #{[row[:missing].size, 8].min} of #{row[:missing].size}): #{sample.join(", ")}"
      end
      out << ""
    end

    if actions[:missing].any?
      out << "## Uncovered actions"
      out << ""
      out << "Endpoints in scope that no row's timeline reaches yet:"
      out << ""
      actions[:missing].each { |action| out << "- `#{action}`" }
      out << ""
    end

    File.write(path, out.join("\n"))
    puts "wrote #{path.relative_path_from(Rails.root)} (#{out.size} lines)"

    write_scenario_inventory
  end

  # Renders a block's cells as a tree, one level per axis, so the shape of the gap is in the
  # indentation rather than repeated on every line.
  #
  #   ✓ covered by a golden row      ~ guarded by a spec outside the suite      · nobody
  def render_cell_tree(block)
    axes = block["axes"]
    lines = []

    walk = lambda do |cells, depth, prefix|
      axis = axes[depth]
      groups = cells.group_by { |cell| cell[axis] }

      groups.each_with_index do |(value, group), index|
        last = index == groups.size - 1
        branch = last ? "└─ " : "├─ "

        if depth == axes.size - 1
          cell = group.first
          mark, note =
            if cell["covered_by"] then ["✓", cell["covered_by"]]
            elsif cell["external"] then ["~", Array(cell["external"]).first]
            else ["·", nil]
            end
          lines << "#{prefix}#{branch}#{value}  #{mark}#{"  #{note}" if note}"
        else
          lines << "#{prefix}#{branch}#{value}"
          walk.call(group, depth + 1, prefix + (last ? "   " : "│  "))
        end
      end
    end

    walk.call(block["cells"], 0, "")
    lines
  end

  # Two renderings of one source: scenarios.json is canonical and diffable, SCENARIOS.md is the same
  # data for humans. Regenerated with COVERAGE.md so the three cannot disagree.
  def write_scenario_inventory
    inventory = GoldenLedger.scenario_summary

    json_path = GoldenMatrix.dir.join("scenarios.json")
    json_path.write(JSON.pretty_generate(inventory) + "\n")
    puts "wrote #{json_path.relative_path_from(Rails.root)} (#{inventory["generated_from_rows"]} scenarios)"

    out = []
    out << "# Golden billing suite — combination map"
    out << ""
    out << "> Generated by `bundle exec rake golden:docs`. Do not edit by hand."
    out << ""
    out << "Every **cell** — one combination of a block's axis values — that the harness can express,"
    out << "and the row covering it if there is one. A blank `row` is a combination nobody has tested."
    out << ""
    out << "| mark | meaning |"
    out << "|---|---|"
    out << "| `✓` | covered by a golden row — exact expected values, derived `math` |"
    out << "| `~` | guarded by a spec outside this suite; weaker, and not counted as covered |"
    out << "| `·` | nobody is testing this combination |"
    out << ""
    out << "The reasoning behind each expected number lives in the `math:` of the row itself, in"
    out << "`matrix/*.yml`. This file is the map, not the explanation."
    out << ""
    covered = inventory["blocks"].sum { |block| block["covered"] }
    writeable = inventory["blocks"].sum { |block| block["writeable"] }
    out << "**#{inventory["generated_from_rows"]} rows covering #{covered} of #{writeable} cells.**"
    out << ""

    # Numeric, not lexical: a plain sort puts B10 between B1 and B2, and not by coverage either —
    # SCENARIOS.md is read as a reference, so a reader looking for B7 should find it between B6 and B8.
    inventory["blocks"].sort_by { |block| block["id"][/\d+/].to_i }.each do |block|
      out << "## #{block["id"]} — #{block["title"]}"
      out << ""
      external = block["cells"].count { |cell| cell["external"] }
      summary = "#{block["covered"]} / #{block["writeable"]} cells"
      summary += " · #{external} also guarded outside the suite" if external.positive?
      out << "#{summary} · axes: #{block["axes"].join(" → ")}"
      out << ""
      out << "```"
      out.concat(render_cell_tree(block))
      out << "```"
      out << ""
    end

    path = GoldenMatrix.dir.join("SCENARIOS.md")
    File.write(path, out.join("\n"))
    puts "wrote #{path.relative_path_from(Rails.root)} (#{out.size} lines)"
  end

  desc "Report which findings are pinned by a row, and which are not"
  task findings: :environment do
    load_golden_support
    summary = GoldenLedger.findings_summary
    puts "#{summary[:pinned_count]} finding(s) pinned by #{summary[:rows_pinning]} row(s)"
    puts
    summary[:pinned].sort.each do |id, row_ids|
      puts format("  %-6s %d row(s)  %s", id, row_ids.size, row_ids.first(3).join(", "))
    end
    puts
    puts "A finding with no pinning row is prose: nothing fails when the behaviour moves."
    puts "Finding ids and evidence live outside the repo, in the session FINDINGS.md."
  end

  desc "Write the dated findings log (PATH=... to choose where)"
  task "findings:export" => :environment do
    load_golden_support

    markdown = GoldenFindings.to_markdown

    path = GoldenMatrix.dir.join("FINDINGS.md")
    path.write(markdown)
    puts "wrote #{path.relative_path_from(Rails.root)} (#{GoldenFindings.acknowledged.size} findings)"

    # A dated copy for whoever wants the log outside the repo. Same content — the ledger is the only
    # source, so a dated file cannot disagree with the committed one.
    if ENV["PATH_OUT"]
      dated = Pathname.new(ENV["PATH_OUT"])
      dated.write(markdown)
      puts "wrote #{dated}"
    end
  end

  desc "Triage state: what is new or changed since the findings ledger was signed off"
  task triage: :environment do
    load_golden_support

    if ENV["REFRESH"]
      updated = GoldenFindings.refresh_digests!
      puts updated.empty? ? "digests already current" : "refreshed digest for #{updated.join(", ")}"
      next
    end

    unacknowledged = GoldenFindings.unacknowledged
    changed = GoldenFindings.changed
    resolved = GoldenFindings.resolved
    untracked = GoldenFindings.untracked

    puts "#{GoldenFindings.observed.size} finding(s) pinned, #{GoldenFindings.acknowledged.size} signed off"
    puts

    if untracked.any?
      puts "UNTRACKED — a characterization row with no `pins:` (#{untracked.size}):"
      puts "  A defect recorded only inside the row that asserts it. Give it a finding id."
      untracked.first(15).each { |f| puts "  #{f["block"]}  #{f["id"]}" }
      puts "  ...and #{untracked.size - 15} more" if untracked.size > 15
      puts
    end

    if unacknowledged.any?
      puts "NEW — recorded by a row, never triaged (#{unacknowledged.size}):"
      unacknowledged.each { |f| puts "  #{f["block"]}  #{f["id"]}\n      #{f["summary"]}" }
      puts
    end

    if changed.any?
      puts "CHANGED — a known defect whose numbers moved (#{changed.size}):"
      changed.each { |f| puts "  #{f["id"]}  #{f["was"]} -> #{f["digest"]}" }
      puts
    end

    if resolved.any?
      puts "RESOLVED — signed off once, no longer in the matrix (#{resolved.size}):"
      resolved.each { |f| puts "  #{f["id"]}" }
      puts
    end

    puts "nothing new" if unacknowledged.empty? && changed.empty? && resolved.empty?
    puts "Sign off with: edit #{GoldenFindings::LEDGER}, or SEED=1 rake golden:findings to rebuild it."
  end

  desc "Record the behaviour surface baseline (spec/scenarios/golden/surface.json)"
  task surface: :environment do
    load_golden_support
    path = GoldenSurface.write!
    puts "wrote #{path.relative_path_from(Rails.root)}"
  end

  # Hand-rendered rather than to_yaml: cells as one flow-style line each, values quoted so "true",
  # "yes" and dates survive the round trip as strings.
  def render_baseline(sha:, recorded_at:, snapshot:)
    out = []
    out << "# The recorded coverage denominator: every legal cell of every block at the recorded sha."
    out << "# Written by `rake golden:baseline`; read by `rake golden:delta` and"
    out << "# GoldenLedger.denominator_delta. Do not edit by hand."
    out << "---"
    out << "sha: #{sha}"
    out << "recorded_at: \"#{recorded_at}\""
    out << "cells_by_block:"
    snapshot.each do |block_id, data|
      out << "  #{block_id}:"
      out << "    axes: [#{data["axes"].join(", ")}]"
      out << "    cells:"
      data["cells"].each { |values| out << "      - [#{values.map(&:inspect).join(", ")}]" }
    end
    out.join("\n") + "\n"
  end

  desc "Record the denominator baseline (spec/scenarios/golden/baseline.yml); pass SHA= where git cannot run"
  task baseline: :environment do
    load_golden_support
    # `api` is a git submodule whose .git is not mounted into the container (see fix_counts above),
    # so HEAD is taken from the environment when git cannot answer.
    sha = ENV["SHA"].presence || `git rev-parse HEAD 2>/dev/null`.strip
    abort "cannot resolve HEAD here — run natively, or pass SHA=$(git rev-parse HEAD)" if sha.empty?

    snapshot = GoldenLedger.denominator_snapshot
    path = GoldenMatrix.dir.join("baseline.yml")
    path.write(render_baseline(sha: sha, recorded_at: Date.current.iso8601, snapshot: snapshot))
    puts "wrote #{path.relative_path_from(Rails.root)} " \
         "(#{snapshot.values.sum { |data| data["cells"].size }} cells across #{snapshot.size} blocks, sha #{sha[0, 12]})"
  end

  desc "Print the cells new since baseline.yml, grouped by block"
  task delta: :environment do
    load_golden_support
    path = GoldenMatrix.dir.join("baseline.yml")
    abort "no baseline recorded — run `rake golden:baseline` first" unless path.exist?

    baseline = YAML.safe_load_file(path, aliases: true)
    delta = GoldenLedger.denominator_delta(against: baseline)

    if delta.empty?
      puts "no new cells since baseline #{baseline["sha"][0, 12]} (recorded #{baseline["recorded_at"]})"
    else
      total = delta.values.sum(&:size)
      puts "#{total} new cell(s) since baseline #{baseline["sha"][0, 12]} (recorded #{baseline["recorded_at"]}):"
      delta.each do |block_id, cells|
        title = GoldenLedger.block_by_id(block_id)&.fetch("title", nil)
        puts
        puts "#{block_id} — #{title}: #{cells.size} new"
        cells.each { |cell| puts "  #{cell.values.join("/")}" }
      end
      puts
      puts "Each is an uncovered combination until a row claims it. Re-record with `rake golden:baseline`."
    end
  end

  desc "Print the row ids the findings ledger declares deliberately red, one per line"
  task expected_reds: :environment do
    load_golden_support
    puts GoldenFindings.expected_reds
  end

  desc "Report new or removed behaviour, and the ranked coverage gaps (report section 3)"
  task discover: :environment do
    load_golden_support
    deltas = GoldenSurface.deltas
    GoldenLedger.summary
    actions = GoldenLedger.action_summary

    puts "NOT COVERED"
    puts

    if deltas.empty?
      puts "  new behaviour surface: none since the recorded baseline"
    else
      puts "  new behaviour surface (#{deltas.size} delta(s)):"
      deltas.first(40).each do |delta|
        sign = (delta[:kind] == "removed") ? "-" : "+"
        subject = delta[:subject].presence ? "#{delta[:subject]} " : ""
        puts "    #{sign} #{delta[:section]} #{subject}#{delta[:detail]}"
      end
      puts "    ... and #{deltas.size - 40} more" if deltas.size > 40
    end

    puts
    puts "  unclaimed cells (ranked by risk):"
    rows = ledger_rows.reject { |row| row[:missing].empty? }.sort_by { |row| -(row[:risk] || 0) }
    rows.first(8).each do |row|
      sample = row[:missing].first(3).map { |cell| cell.values.join("/") }
      puts format("    %-5s %-34s %3d uncovered  risk %-6s e.g. %s", row[:id], row[:title].to_s[0, 34], row[:missing].size, row[:risk] || "—", sample.join(", "))
    end

    if actions[:missing].any?
      puts
      puts "  unclaimed actions (#{actions[:missing].size}):"
      actions[:missing].first(12).each { |action| puts "    #{action}" }
      puts "    ... and #{actions[:missing].size - 12} more" if actions[:missing].size > 12
    end
  end

  desc "Write machine-readable state to tmp/golden/state.json (consumed by dev/golden/report.rb)"
  task state: :environment do
    load_golden_support
    dir = Rails.root.join("tmp/golden")
    dir.mkpath

    rows = ledger_rows
    state = {
      "blocks" => rows.map do |row|
        {
          "id" => row[:id], "title" => row[:title], "rows" => row[:rows], "legal" => row[:legal],
          "covered" => row[:covered], "percent" => row[:percent], "uncovered" => row[:uncovered],
          "fixes" => row[:fixes], "risk" => row[:risk], "services" => row[:services],
          "missing" => row[:missing].first(20), "illegal" => row[:illegal],
          "malformed" => row[:malformed].map { |m| m.transform_keys(&:to_s) }
        }
      end,
      "totals" => GoldenLedger.totals.transform_keys(&:to_s),
      "actions" => GoldenLedger.action_summary.transform_keys(&:to_s),
      "surface_deltas" => GoldenSurface.deltas.map { |delta| delta.transform_keys(&:to_s) },
      "rows_by_id" => GoldenMatrix.rows.to_h { |row| [row["id"], {"block" => row["block"], "file" => row["__file"]}] }
    }

    path = dir.join("state.json")
    path.write(JSON.pretty_generate(state) + "\n")
    puts "wrote #{path.relative_path_from(Rails.root)}"
  end
end
