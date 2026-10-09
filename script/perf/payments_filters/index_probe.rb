# frozen_string_literal: true

# Builds one candidate index with CREATE INDEX CONCURRENTLY, times it, reports its
# size and INVALID state, then optionally runs explain.rb on a subset of cases.
# Throwaway perf database only.
#
#   PERF_INDEX_NAME=perf_a_status PERF_INDEX_DDL="ON payments (organization_id, payable_payment_status, created_at DESC, id)" \
#   PERF_PHASE=idx_a PERF_ONLY='^status_' bundle exec rails runner script/perf/payments_filters/index_probe.rb
#
# PERF_INDEX_DROP=1 drops the index instead (CONCURRENTLY). Output goes to stdout;
# build times and sizes are the figures quoted for G7 in the internal document.

raise "This script is only for development" unless Rails.env.development?

ActiveRecord::Base.logger = Logger.new(nil)
conn = ApplicationRecord.connection
abort "database name must contain perf" unless conn.current_database.include?("perf") || ENV["PERF_ALLOW_DB"] == "1"

name = ENV.fetch("PERF_INDEX_NAME")
if ENV["PERF_INDEX_DROP"] == "1"
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  conn.execute("DROP INDEX CONCURRENTLY IF EXISTS #{conn.quote_table_name(name)}")
  puts format("dropped %s in %.1fs", name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0)
  exit
end

ddl = "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{conn.quote_table_name(name)} #{ENV.fetch("PERF_INDEX_DDL")}"
puts ddl
conn.execute("SET statement_timeout = 0")
conn.execute(ENV["PERF_SESSION_SQL"]) if ENV["PERF_SESSION_SQL"].present?
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
conn.execute(ddl)
secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
row = conn.select_one(<<~SQL)
  SELECT pg_size_pretty(pg_relation_size(i.indexrelid)) AS size, pg_relation_size(i.indexrelid) AS bytes, x.indisvalid
  FROM pg_stat_user_indexes i JOIN pg_index x ON x.indexrelid = i.indexrelid
  WHERE i.indexrelname = #{conn.quote(name)}
SQL
puts format("built %s in %.1fs size=%s valid=%s", name, secs, row["size"], row["indisvalid"])
conn.execute("ANALYZE #{ddl[/ON (\w+)/, 1]}")

if ENV["PERF_ONLY"]
  ENV["PERF_PHASE"] ||= "idx_#{name}"
  load Rails.root.join("script/perf/payments_filters/explain.rb")
end
