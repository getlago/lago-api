# frozen_string_literal: true

# Produces the golden suite's run report: three sections, then a proposal, then nothing.
#
#   ① NOT PERFORMING AS EXPECTED   failures with no commit that explains them — suspected regressions
#   ② CHANGED                      failures a commit does explain — intended behaviour changes
#   ③ NOT COVERED                  new behaviour surface, plus the ranked coverage and action gaps
#
# Runs on the HOST because the ①/② split needs git, and `api` is a submodule whose real .git
# directory is not mounted into the container.
#
#   ruby dev/golden/report.rb                 # whole matrix
#   ruby dev/golden/report.rb --block B6      # one block
#   ruby dev/golden/report.rb --mark-green    # on a green run, record the sha as the new baseline
#
# This script writes nothing except tmp/golden/. It reports and proposes; it never edits a row.
# Applying a proposal is a separate, deliberate act — see the guardrail in the README.
#
# Exit codes: 0 all green · 1 suspected regressions · 2 only intended changes · 3 could not run.

# A standalone host script run with the system ruby, not Rails code.
# Rails/IndexBy is disabled too: index_by is ActiveSupport, which is not loaded here.
# rubocop:disable Rails/Output, Rails/Exit, Lint/RedundantRequireStatement, Rails/IndexBy
require "json"
require "open3"
require "pathname"

ROOT = Pathname.new(__dir__).join("../..").expand_path
LAGO = ROOT.parent
TMP = ROOT.join("tmp/golden")
COMPOSE = ENV.fetch("GOLDEN_COMPOSE", "docker compose -f #{LAGO.join("docker-compose.dev.yml")}")
BLOCK = ARGV.each_cons(2).find { |flag, _| flag == "--block" }&.last
MARK_GREEN = ARGV.include?("--mark-green")

def sh(command)
  stdout, stderr, status = Open3.capture3(command)
  [stdout, stderr, status.success?]
end

def in_container(command)
  sh(%(#{COMPOSE} exec -T -e RAILS_ENV=test -e LAGO_DISABLE_SCHEMA_DUMP=true api #{command}))
end

def head_sha
  sh("git -C #{ROOT} rev-parse --short HEAD").first.strip
end

# ---------------------------------------------------------------- run

TMP.mkpath
rspec_out = TMP.join("rspec.json")
rspec_out.delete if rspec_out.exist?

filter = BLOCK ? %(-e "#{BLOCK}") : ""
puts "running spec/scenarios/golden#{" (#{BLOCK})" if BLOCK} ..."
_out, err, _ok = in_container(%(bundle exec rspec spec/scenarios/golden #{filter} --format json --out tmp/golden/rspec.json))

unless rspec_out.exist?
  warn "rspec produced no report — could not run:\n#{err}"
  exit 3
end

results = JSON.parse(rspec_out.read)
in_container("bundle exec rake golden:state")
state_path = TMP.join("state.json")
unless state_path.exist?
  warn "rake golden:state produced no state.json"
  exit 3
end
state = JSON.parse(state_path.read)

# ---------------------------------------------------------------- classify

last_green_path = TMP.join("last_green.json")
last_green = last_green_path.exist? ? JSON.parse(last_green_path.read) : nil
blocks_by_id = state.fetch("blocks").to_h { |block| [block["id"], block] }
rows_by_id = state.fetch("rows_by_id")

# A row id is the example description, so it is recoverable from the full description.
def row_id_for(example, rows_by_id)
  rows_by_id.keys.find { |id| example["full_description"].to_s.include?(id) }
end

# Commits since the last green run that touch the services this block owns. Evidence, not vibes:
# with no such commit the failure stays in ①, however plausible the new value looks.
def explaining_commits(services, since_sha)
  paths = services.select { |path| ROOT.join(path).exist? }
  return [] if paths.empty? || since_sha.nil?

  range = "#{since_sha}..HEAD"
  log, _err, ok = sh("git -C #{ROOT} log #{range} --no-merges --pretty=format:%h%x09%s -- #{paths.join(" ")}")
  return [] unless ok

  log.dup.force_encoding("UTF-8").scrub("").lines.map(&:strip).reject(&:empty?)
end

# The runner's failure messages are shaped so old → new is recoverable:
#   "<field>: expected <a>, got <b>"
#   "fee #<n>: <field> expected <a>, got <b>"
#   "usage[<code>]: <field> expected <a>, got <b>"
def parse_deltas(message)
  message.to_s.scan(/^\s*(?:(fee #\d+|usage\[[^\]]+\]):\s*)?([a-z_]+):?\s*expected\s+(.+?),\s*got\s+(.+?)\s*$/)
    .map { |scope, field, expected, actual| {scope: scope, field: field, expected: expected, actual: actual} }
end

failures = results.fetch("examples").select { |example| example["status"] == "failed" }
regressions = []
changes = []

failures.each do |example|
  row_id = row_id_for(example, rows_by_id)
  row = row_id ? rows_by_id[row_id] : nil
  block = row ? blocks_by_id[row["block"]] : nil
  commits = block ? explaining_commits(block["services"], last_green&.dig("sha")) : []

  entry = {
    id: row_id || example["full_description"],
    file: row&.dig("file"),
    block: row&.dig("block"),
    message: example.dig("exception", "message").to_s.strip,
    deltas: parse_deltas(example.dig("exception", "message")),
    commits: commits
  }
  commits.empty? ? regressions << entry : changes << entry
end

# ---------------------------------------------------------------- report

totals = state.fetch("totals")
actions = state.fetch("actions")
deltas = state.fetch("surface_deltas")

puts
puts "GOLDEN BILLING — #{BLOCK || "all blocks"} · runner: rspec · api @ #{head_sha}"
puts last_green ? "last green: #{last_green["sha"]} (#{last_green["at"]})" : "last green: none recorded — ①/② cannot be split until a green run is marked"
puts

puts "① NOT PERFORMING AS EXPECTED — #{regressions.size} suspected regression#{"s" unless regressions.size == 1}"
if regressions.empty?
  puts "  none"
else
  regressions.each do |entry|
    puts "  FAIL #{entry[:id]}#{" [#{entry[:block]}]" if entry[:block]}"
    entry[:deltas].each { |d| puts "       #{[d[:scope], d[:field]].compact.join(" ")}: expected #{d[:expected]}, got #{d[:actual]}" }
    puts "       #{entry[:message].lines.first.to_s.strip}" if entry[:deltas].empty?
    puts "       no commit since last green touches this block's services — UNEXPLAINED"
    puts "       → reported only. Expectation NOT changed, no proposal generated."
  end
end
puts

puts "② CHANGED — #{changes.size} intended behaviour change#{"s" unless changes.size == 1}"
if changes.empty?
  puts "  none"
else
  changes.each do |entry|
    puts "  FAIL #{entry[:id]}#{" [#{entry[:block]}]" if entry[:block]}"
    entry[:deltas].each { |d| puts "       #{[d[:scope], d[:field]].compact.join(" ")}: expected #{d[:expected]}, got #{d[:actual]}" }
    entry[:commits].first(5).each { |commit| puts "       explained by #{commit}" }
    puts "       → expectation update proposed below"
  end
end
puts

puts "③ NOT COVERED"
if deltas.empty?
  puts "  new behaviour surface: none since the recorded baseline"
else
  puts "  new behaviour surface (#{deltas.size} delta#{"s" unless deltas.size == 1}):"
  deltas.first(20).each do |delta|
    sign = (delta["kind"] == "removed") ? "-" : "+"
    puts "    #{sign} #{delta["section"]} #{"#{delta["subject"]} " unless delta["subject"].to_s.empty?}#{delta["detail"]}"
  end
  puts "    ... and #{deltas.size - 20} more" if deltas.size > 20
end
puts "  unclaimed cells (ranked by risk):"
state.fetch("blocks").reject { |b| b["uncovered"].zero? }.sort_by { |b| -(b["risk"] || 0) }.first(5).each do |b|
  sample = b["missing"].first(3).map { |cell| cell.values.join("/") }
  puts format("    %-5s %3d uncovered  risk %-6s e.g. %s", b["id"], b["uncovered"], b["risk"] || "—", sample.join(", "))
end
puts "  unclaimed actions: #{actions["missing"].size} of #{actions["total"]} in scope"
puts

puts "COVERAGE  cells #{totals["covered"]}/#{totals["legal"]} (#{totals["percent"]}%) · actions #{actions["covered"]}/#{actions["total"]} (#{actions["percent"]}%)"
summary = results.fetch("summary")
puts "VERDICT   #{summary["example_count"] - summary["failure_count"]} PASS · #{regressions.size} FAIL(regression) · " \
     "#{changes.size} FAIL(changed) · #{summary["pending_count"]} pending"
puts

# ---------------------------------------------------------------- proposal

if changes.any? || deltas.any?
  puts "PROPOSED CHANGES — nothing written yet"
  puts
  if changes.any?
    puts "  UPDATE #{changes.size} expectation#{"s" unless changes.size == 1}"
    changes.each do |entry|
      puts "    #{entry[:id]}  (#{entry[:file]})"
      entry[:deltas].each { |d| puts "      #{[d[:scope], d[:field]].compact.join(" ")}   #{d[:expected]} → #{d[:actual]}" }
      puts "      math: must be re-derived, not re-typed"
      puts "      CHANGELOG.md += row id · old → new · #{entry[:commits].first.to_s.split("\t").first} · why"
    end
    puts
  end
  if deltas.any?
    puts "  ADD rows for #{deltas.size} surface delta#{"s" unless deltas.size == 1} (see ③)"
    puts
  end
  puts "Apply?  [ all | updates only | additions only | none ]"
  puts "`none` is always valid and leaves the suite red."
else
  puts "No changes proposed."
end

if MARK_GREEN
  if BLOCK
    # The marker is the baseline for the WHOLE suite, so a filtered run must not set it: marking
    # green off one block would silently declare the other fifteen green too.
    warn "\nrefusing --mark-green: the green marker is suite-wide and this run was filtered to #{BLOCK}"
  elsif failures.empty?
    last_green_path.write(JSON.pretty_generate("sha" => head_sha, "at" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")) + "\n")
    puts
    puts "marked green at #{head_sha}"
  else
    warn "\nrefusing --mark-green: #{failures.size} failure(s)"
  end
end

exit 0 if failures.empty?
exit 1 if regressions.any?
exit 2
# rubocop:enable Rails/Output, Rails/Exit, Lint/RedundantRequireStatement, Rails/IndexBy
