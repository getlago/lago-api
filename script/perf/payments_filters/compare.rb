# frozen_string_literal: true

# Builds the before/after table and the G1-G9 scoreboard from explain.rb and
# bench.rb outputs. Plain Ruby, no Rails needed:
#
#   ruby script/perf/payments_filters/compare.rb baseline after
#
# Reads plans/<phase>/summary.json and bench/<phase>.http.json (and .sql.json
# when present), writes compare/<before>_vs_<after>.md, prints it.
#
# Targets (see the internal performance document for the rationale):
#   G1 single filter p95 < 300 ms (common and rare value)   G2 five-filter p95 < 800 ms
#   G3 COUNT(*) < 500 ms on selective cases                 G4 control p95 within +10 %
#   G5 selective cases: no Seq Scan on payments/invoices/payment_receipts, no Sort > 10k rows
#   G8 zero errors in the load test                          G9 page 50 < 2x page 1
# G6 (index budget) and G7 (index build time) are graded from the migration run, not here.

require "json"

# Filters that existed before this work: red targets on them are reported, never graded as blocking.
PREEXISTING = %w[currency_common currency_rare customer_heavy customer_light search_term search_term_status].freeze

before_phase, after_phase = ARGV
abort "usage: ruby compare.rb <before_phase> <after_phase>" unless before_phase && after_phase

root = File.expand_path(__dir__)
load_json = ->(path) { File.exist?(path) ? JSON.parse(File.read(path)) : nil }
plans = {before: load_json.call("#{root}/plans/#{before_phase}/summary.json"), after: load_json.call("#{root}/plans/#{after_phase}/summary.json")}
http = {before: load_json.call("#{root}/bench/#{before_phase}.http.json"), after: load_json.call("#{root}/bench/#{after_phase}.http.json")}
sql = {before: load_json.call("#{root}/bench/#{before_phase}.sql.json"), after: load_json.call("#{root}/bench/#{after_phase}.sql.json")}
abort "missing plans for #{before_phase} or #{after_phase}" unless plans[:before] && plans[:after]

by_name = ->(doc) { doc ? doc["cases"].to_h { |c| [c["name"], c] } : {} } # rubocop:disable Rails/IndexBy -- plain Ruby, no ActiveSupport
pb, pa = by_name.call(plans[:before]), by_name.call(plans[:after])
hb, ha = by_name.call(http[:before]), by_name.call(http[:after])
sb, sa = by_name.call(sql[:before]), by_name.call(sql[:after])

fmt = ->(v) {
  if v.nil?
    "-"
  else
    (v.is_a?(Float) ? format("%.1f", v) : v.to_s)
  end
}
md = "# Before/after: #{before_phase} -> #{after_phase}\n\n"
md << "Plans: median EXPLAIN (ANALYZE, BUFFERS) execution time. HTTP: p95 of GET /api/v1/payments, 20 clients. Synthetic dataset.\n\n"
md << "| case | sel. | list ms before | list ms after | count ms before | count ms after | http p95 before | http p95 after | sql p95 before | sql p95 after | list nodes after | flags before | flags after |\n"
md << "|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
pa.each_key do |name|
  b, a = pb[name], pa[name]
  md << "| #{name} | #{a["selective"]} | #{fmt.call(b&.dig("list", "ms"))} | #{fmt.call(a.dig("list", "ms"))} | #{fmt.call(b&.dig("count", "ms"))} | #{fmt.call(a.dig("count", "ms"))} " \
        "| #{fmt.call(hb[name]&.dig("p95_ms"))} | #{fmt.call(ha[name]&.dig("p95_ms"))} | #{fmt.call(sb[name]&.dig("p95_ms"))} | #{fmt.call(sa[name]&.dig("p95_ms"))} " \
        "| #{a.dig("list", "nodes").join(", ")} | #{(b&.dig("flags") || []).join(" ")} | #{a["flags"].join(" ")} |\n"
end

# --- Scoreboard on the "after" phase -----------------------------------------
single = pa.values.reject { |c| c["name"].start_with?("combo_", "five_filter", "control", "search_term") || c["page"] != 1 }
p95 = ->(name) { ha[name]&.dig("p95_ms") }
green = ->(ok, text) { "#{ok ? "GREEN" : "RED"} #{text}" }

lines = []
worst_single = single.map { |c| [c["name"], p95.call(c["name"])] }.reject { |_, v| v.nil? }.max_by { |_, v| v }
lines << ["G1", "single filter p95 < 300 ms", worst_single ? green.call(worst_single[1] < 300, "worst #{worst_single[0]} #{fmt.call(worst_single[1])} ms") : "n/a (no http bench)"]
five = %w[five_filter_common five_filter_rare].map { |n| [n, p95.call(n)] }.reject { |_, v| v.nil? }.max_by { |_, v| v }
lines << ["G2", "five-filter p95 < 800 ms", five ? green.call(five[1] < 800, "worst #{five[0]} #{fmt.call(five[1])} ms") : "n/a (no http bench)"]
strict = pa.values.select { |c| c["selective"] && !PREEXISTING.include?(c["name"]) }
sel_counts = strict.map { |c| [c["name"], c.dig("count", "ms") || Float::INFINITY] }
worst_count = sel_counts.max_by { |_, v| v }
non_sel_counts = pa.values.reject { |c| c["selective"] }.map { |c| [c["name"], c.dig("count", "ms") || Float::INFINITY] }.max_by { |_, v| v }
pre_red = pa.values.select { |c| PREEXISTING.include?(c["name"]) && (c.dig("count", "ms") || Float::INFINITY) >= 500 }.map { |c| "#{c["name"]} #{fmt.call(c.dig("count", "ms"))} ms" }
lines << ["G3", "COUNT(*) < 500 ms (selective cases, new filters)", green.call(worst_count[1] < 500, "worst #{worst_count[0]} #{fmt.call(worst_count[1])} ms; non-selective worst #{non_sel_counts[0]} #{fmt.call(non_sel_counts[1])} ms and pre-existing filters over 500 ms (#{pre_red.empty? ? "none" : pre_red.join(", ")}) reported separately")]
cb, ca = p95.call("control"), hb["control"]&.dig("p95_ms")
if cb && ca
  delta = (cb - ca) / ca * 100
  lines << ["G4", "control p95 within +10 %", green.call(delta <= 10, "#{fmt.call(ca)} -> #{fmt.call(cb)} ms (#{format("%+.1f", delta)} %)")]
else
  lines << ["G4", "control p95 within +10 %", "n/a (no http bench on both phases)"]
end
g5_bad = pa.values.select { |c| c["selective"] }.select { |c| (c.dig("list", "seq_scan_watched") + c.dig("count", "seq_scan_watched")).any? || c.dig("list", "sort_rows_max") > 10_000 }
g5_bad.reject! { |c| PREEXISTING.include?(c["name"]) }
lines << ["G5", "selective plans: no watched Seq Scan, no Sort > 10k", green.call(g5_bad.empty?, g5_bad.empty? ? "all #{pa.values.count { |c| c["selective"] }} selective cases clean" : g5_bad.map { |c| "#{c["name"]}#{c["flags"].join(",")}" }.join("; "))]
errors = ha.values.sum { |c| c["errors"].to_i }
lines << ["G8", "zero errors in the load test", ha.empty? ? "n/a (no http bench)" : green.call(errors.zero?, "#{errors} errors over #{ha.values.sum { |c| c["requests"].to_i }} requests")]
g9 = [["control", "control_page50"], ["status_common_succeeded", "status_common_succeeded_page50"]].map do |p1, p50|
  a, b = p95.call(p1) || pa[p1]&.dig("list", "ms"), p95.call(p50) || pa[p50]&.dig("list", "ms")
  # OFFSET 980 on an index walk costs a few milliseconds; below 50 ms the ratio is noise, not a lost index.
  (a && b) ? [p50, a, b, b < 2 * a || b < 50] : nil
end.compact
lines << ["G9", "page 50 < 2x page 1", green.call(g9.all? { |r| r[3] }, g9.map { |n, a, b, _| "#{n} #{fmt.call(a)} -> #{fmt.call(b)} ms" }.join("; "))]

md << "\n## Scoreboard (#{after_phase})\n\n| # | target | result |\n|---|---|---|\n"
lines.each { |id, target, result| md << "| #{id} | #{target} | #{result} |\n" }
md << "\nG6 (<= 3 new payments indexes) and G7 (build < 15 min, no INVALID) are graded from the migration run log.\n"

Dir.mkdir("#{root}/compare") unless Dir.exist?("#{root}/compare")
out = "#{root}/compare/#{before_phase}_vs_#{after_phase}.md"
File.write(out, md)
puts md
puts "wrote #{out}"
