# frozen_string_literal: true

# Captures EXPLAIN (ANALYZE, BUFFERS) plans for every case of the payments list
# filters matrix, going through PaymentsQuery itself so the SQL is the one the
# API runs (base scope, visibility condition, LIMIT/OFFSET, and the COUNT(*)
# Kaminari issues for meta.total_count).
#
#   DATABASE_URL=postgresql://lago:changeme@db:5432/lago_perf \
#     PERF_PHASE=baseline bundle exec rails runner script/perf/payments_filters/explain.rb
#
# Env: PERF_PHASE (baseline|after|iterN, default baseline), PERF_ONLY (regex on
# case names), PERF_RUNS (default 3, median kept), PERF_ORG_SLUG (default perf-big),
# PERF_TIMEOUT (statement timeout per EXPLAIN, default 120s), PERF_SESSION_SQL (planner
# settings for the session, e.g. "SET random_page_cost = 4"), PERF_COUNT_VARIANTS=1 to
# also time two alternative counts per case: capped (LIMIT 10001, the
# BaseQuery::CappedTotalCount shape) and without the invoice visibility condition
# (to measure the share of the correlated EXISTS in the COUNT).
#
# Output: script/perf/payments_filters/plans/<phase>/<case>.txt and
# <case>.count.txt (SQL + median plan), summary.json and summary.md.
# Organization UUIDs are redacted from the saved plans.

raise "This script is only for development" unless Rails.env.development?

require "json"
require_relative "cases"
require_relative "plan_stats"
ActiveRecord::Base.logger = Logger.new(nil) # keep stdout readable; SQL is in the saved plans

PHASE = ENV.fetch("PERF_PHASE", "baseline")
ONLY = ENV["PERF_ONLY"] && Regexp.new(ENV["PERF_ONLY"])
RUNS = Integer(ENV.fetch("PERF_RUNS", 3))
TIMEOUT = ENV.fetch("PERF_TIMEOUT", "120s")
COUNT_VARIANTS = ENV["PERF_COUNT_VARIANTS"] == "1"

organization = Organization.find_by!(slug: ENV.fetch("PERF_ORG_SLUG", "perf-big"))
conn = ApplicationRecord.connection
# Optional planner settings for the session, e.g. PERF_SESSION_SQL="SET random_page_cost = 4".
# Used to check that an index decision does not hinge on one cost parameter.
if ENV["PERF_SESSION_SQL"].present?
  conn.execute(ENV["PERF_SESSION_SQL"])
  puts "session: #{ENV["PERF_SESSION_SQL"]}"
end
out_dir = Rails.root.join("script/perf/payments_filters/plans", PHASE)
FileUtils.mkdir_p(out_dir)

values = PaymentsFiltersPerf::Cases.resolve_values(organization)
cases = PaymentsFiltersPerf::Cases.matrix(values)
cases.select! { |c| c[:name].match?(ONLY) } if ONLY
puts "phase=#{PHASE} org=#{organization.slug} cases=#{cases.size} runs=#{RUNS}"
puts "resolved values: #{values.except(:max_created).to_json}"

# The exact COUNT(*) statement Kaminari runs for total_count, captured from the notification stream.
def capture_count_sql(relation)
  captured = nil
  callback = ->(_name, _start, _finish, _id, payload) { captured = payload[:sql] if payload[:sql].start_with?("SELECT COUNT") }
  ApplicationRecord.connection.unprepared_statement do
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { relation.total_count }
  end
  captured
end

def explain(conn, sql)
  conn.execute("SET statement_timeout = '#{TIMEOUT}'")
  conn.execute("EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) #{sql}").values.flatten.join("\n")
rescue ActiveRecord::QueryCanceled
  "TIMEOUT after #{TIMEOUT}"
ensure
  conn.execute("RESET statement_timeout")
end

# Committed plans carry no identifiers: the organization id becomes <org-uuid>, every other
# UUID literal (provider, customer, invoice, request ids resolved by the query) becomes <uuid>.
UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
redact = ->(text) { text.gsub(organization.id, "<org-uuid>").gsub(UUID, "<uuid>") }

summary = []
statements_per_case = COUNT_VARIANTS ? 4 : 2
cases.each do |kase|
  result = PaymentsQuery.call(organization:, filters: kase[:filters], search_term: kase[:search_term],
    pagination: {page: kase[:page], limit: 20})
  raise "PaymentsQuery failed for #{kase[:name]}: #{result.error.inspect}" unless result.success?

  relation = result.payments
  list_sql = relation.to_sql
  count_sql = capture_count_sql(relation)

  statements = {list: list_sql, count: count_sql}
  if COUNT_VARIANTS
    bare = relation.except(:offset, :limit, :order, :includes, :preload, :eager_load)
    statements[:count_capped] = "SELECT COUNT(*) FROM (#{bare.limit(BaseQuery::CappedTotalCount::MAX_COUNTED_RECORDS + 1).select(:id).to_sql}) capped"
    query = PaymentsQuery.new(organization:, filters: kase[:filters], search_term: kase[:search_term], pagination: {page: 1, limit: 20})
    query.send(:validate_filters)
    no_visibility = Payment.where.not(customer_id: nil).where(organization:).where.not(payable_id: nil)
    no_visibility = no_visibility.where(id: query.send(:matching_ids_by_search)) if kase[:search_term].present?
    statements[:count_no_visibility] = query.send(:apply_filters, no_visibility).select("COUNT(*)").to_sql
  end

  entry = {name: kase[:name], page: kase[:page], selective: kase[:selective], filters: kase[:filters], search_term: kase[:search_term]}
  statements.each do |kind, sql|
    if sql.nil?
      # ActiveRecord short-circuits an empty IN () list and answers without a query.
      entry[kind] = PaymentsFiltersPerf::PlanStats.analyse("Result (no query: ActiveRecord short-circuits an empty IN list)  (actual time=0.000..0.000 rows=0 loops=1)\nExecution Time: 0.000 ms")
      entry[kind][:all_runs_ms] = [0.0]
      File.write(out_dir.join("#{kase[:name]}#{".#{kind}" unless kind == :list}.txt"), "-- case: #{kase[:name]} (#{kind}) phase: #{PHASE} selective: #{kase[:selective]}\n-- filters: #{kase[:filters].to_json} search_term: #{kase[:search_term].inspect} page: #{kase[:page]}\n-- runs_ms: [0.0]\n(no query)\n\nResult (no query: ActiveRecord short-circuits an empty IN list)  (actual time=0.000..0.000 rows=0 loops=1)\nExecution Time: 0.000 ms\n")
      next
    end
    plans = Array.new(RUNS) { explain(conn, sql) }
    median = plans.sort_by { |p| PaymentsFiltersPerf::PlanStats.execution_ms(p) || Float::INFINITY }[plans.size / 2]
    stats = PaymentsFiltersPerf::PlanStats.analyse(median)
    stats[:all_runs_ms] = plans.map { |p| PaymentsFiltersPerf::PlanStats.execution_ms(p)&.round(1) }
    entry[kind] = stats
    file = out_dir.join("#{kase[:name]}#{".#{kind}" unless kind == :list}.txt")
    File.write(file, redact.call("-- case: #{kase[:name]} (#{kind}) phase: #{PHASE} selective: #{kase[:selective]}\n-- filters: #{kase[:filters].to_json} search_term: #{kase[:search_term].inspect} page: #{kase[:page]}\n-- runs_ms: #{stats[:all_runs_ms].inspect}\n#{sql}\n\n#{median}\n"))
  end

  flags = PaymentsFiltersPerf::PlanStats.flags(entry[:list], entry[:count])
  entry[:flags] = flags
  summary << entry
  variants = COUNT_VARIANTS ? format("  capped %8.1f ms  no-vis %8.1f ms", entry[:count_capped][:ms] || -1, entry[:count_no_visibility][:ms] || -1) : ""
  puts format("%-34s list %9.1f ms  count %9.1f ms  rows=%-6d cursor=%-5s %s%s", kase[:name], entry[:list][:ms] || -1, entry[:count][:ms] || -1,
    entry[:list][:rows_returned], entry[:list][:cursor_index], flags.join(" "), variants)
end

# With PERF_ONLY, merge into an existing summary so a partial rerun does not drop the other cases.
summary_path = out_dir.join("summary.json")
if ONLY && File.exist?(summary_path)
  previous = JSON.parse(File.read(summary_path), symbolize_names: true)[:cases]
  summary = (previous.reject { |c| summary.any? { |n| n[:name] == c[:name] } } + summary).sort_by { |c| c[:name] }
end
File.write(summary_path, JSON.pretty_generate({phase: PHASE, generated_at: Time.current.iso8601, runs: RUNS,
  values: values.except(:max_created), cases: summary}))

md = PaymentsFiltersPerf::PlanStats.summary_markdown(PHASE, summary, runs: RUNS, variants: COUNT_VARIANTS)
File.write(out_dir.join("summary.md"), md)
puts "wrote #{out_dir}/summary.{md,json} and #{summary.size * statements_per_case} plan files"
