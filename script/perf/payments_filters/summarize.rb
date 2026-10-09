# frozen_string_literal: true

# Rebuilds plans/<phase>/summary.json and summary.md from the saved plan files.
# Plain Ruby, no Rails: ruby script/perf/payments_filters/summarize.rb <phase>
# Useful when explain.rb was interrupted, or to re-derive the tables from the
# committed plans.

require "json"
require_relative "plan_stats"

phase = ARGV.first or abort "usage: ruby summarize.rb <phase>"
dir = File.join(__dir__, "plans", phase)
files = Dir[File.join(dir, "*.txt")]
abort "no plans in #{dir}" if files.empty?

entries = {}
files.sort.each do |file|
  text = File.read(file)
  header = text[/\A-- case: (\S+) \((\w+)\) phase: \S+(?: selective: (\w+))?\n-- filters: (.*) search_term: (.*) page: (\d+)\n(?:-- runs_ms: (.*)\n)?/]
  next unless header
  name, kind, selective, filters, search_term, page, runs = Regexp.last_match.captures
  plan = text.split("\n\n", 2).last
  entry = (entries[name] ||= {name:, page: page.to_i, selective: selective == "true", filters: JSON.parse(filters), search_term: (search_term == "nil") ? nil : search_term.delete('"')})
  stats = PaymentsFiltersPerf::PlanStats.analyse(plan)
  stats[:all_runs_ms] = begin
    runs && JSON.parse(runs)
  rescue
    nil
  end
  entry[kind.to_sym] = stats
end

summary = entries.values.select { |e| e[:list] && e[:count] }
summary.each { |e| e[:flags] = PaymentsFiltersPerf::PlanStats.flags(e[:list], e[:count]) }
variants = summary.any? { |e| e[:count_capped] }
File.write(File.join(dir, "summary.json"), JSON.pretty_generate({phase:, rebuilt_from_plans: true, cases: summary}))
File.write(File.join(dir, "summary.md"), PaymentsFiltersPerf::PlanStats.summary_markdown(phase, summary, runs: "n (see plan headers)", variants:))
puts "#{summary.size} cases -> #{dir}/summary.{json,md}"
summary.each { |e| puts format("%-34s list %10s ms  count %10s ms  %s", e[:name], e[:list][:ms] || "timeout", e[:count][:ms] || "timeout", e[:flags].join(" ")) }
