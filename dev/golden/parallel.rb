#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the golden suite across several lanes, each with its own database.
#
# Why this exists rather than `parallel_rspec`: every row in the matrix becomes an example in ONE
# file, golden_spec.rb, and parallel_tests divides work by FILE. It would hand the whole suite to one
# lane. So the split happens inside the spec (`GOLDEN_SHARD=<n>/<total>`) and this script drives it.
#
# Each lane needs its own database because the `no_transaction` rows use DatabaseCleaner's deletion
# strategy, which truncates shared tables — two lanes on one database is the deadlock recorded as
# F88/F89, not merely a slowdown. Lane databases are CLONED from lago_test with
# `CREATE DATABASE ... TEMPLATE`, which is near-instant and cannot drift from the schema.
#
# Usage, from inside the api container:
#   ruby dev/golden/parallel.rb            # 6 lanes
#   LANES=4 ruby dev/golden/parallel.rb
#   ruby dev/golden/parallel.rb spec/scenarios/golden/golden_spec.rb -e "B17"

LANES = Integer(ENV.fetch("LANES", "6"))
BASE_URL = ENV["DATABASE_TEST_URL"] or abort "DATABASE_TEST_URL is not set"
BASE_DB = BASE_URL.split("/").last
ARGS = ARGV.empty? ? ["spec/scenarios/golden/golden_spec.rb"] : ARGV

def psql(database, sql)
  admin = BASE_URL.sub(%r{/[^/]+\z}, "/postgres")
  system("psql", admin, "-v", "ON_ERROR_STOP=1", "-q", "-c", sql, out: File::NULL, err: File::NULL) ||
    warn("  ! #{database}: #{sql.split.first(4).join(" ")} failed")
end

def lane_url(lane)
  lane == 1 ? BASE_URL : "#{BASE_URL}_#{lane}"
end

def sessions_on(database)
  admin = BASE_URL.sub(%r{/[^/]+\z}, "/postgres")
  IO.popen(["psql", admin, "-tAc", "SELECT count(*) FROM pg_stat_activity WHERE datname = '#{database}'"], &:read).to_i
end

# A backend already on a lane database is a run in progress. Joining it is the F88/F89
# self-deadlock, and clearing it kills a run that is not ours (F90) — so refuse instead.
busy = (1..LANES).map { |lane| lane_url(lane).split("/").last }.select { |db| sessions_on(db).positive? }
abort "refusing to start: active sessions on #{busy.join(", ")} — another run owns them (F88/F89)" if busy.any?

puts "Preparing #{LANES} lane(s) from #{BASE_DB}"
(2..LANES).each do |lane|
  name = "#{BASE_DB}_#{lane}"
  # Terminate stragglers first: a lane left connected makes the template unusable and the clone fails
  # with a message that looks nothing like the cause.
  psql(name, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '#{BASE_DB}' AND pid <> pg_backend_pid()")
  psql(name, "DROP DATABASE IF EXISTS #{name}")
  psql(name, "CREATE DATABASE #{name} TEMPLATE #{BASE_DB}")
  puts "  #{name}"
end

started = Time.now
pids = (1..LANES).map do |lane|
  log = "tmp/golden-lane-#{lane}.log"
  Process.spawn(
    {"GOLDEN_SHARD" => "#{lane}/#{LANES}", "DATABASE_TEST_URL" => lane_url(lane),
     "RAILS_ENV" => "test", "LAGO_DISABLE_SCHEMA_DUMP" => "true"},
    "bundle", "exec", "rspec", *ARGS,
    out: log, err: [:child, :out]
  )
end

puts "Running #{LANES} lane(s)..."
results = pids.each_with_index.map { |pid, i| [i + 1, Process.waitpid2(pid).last.exitstatus] }
elapsed = (Time.now - started).round(1)

puts "\n#{"-" * 60}"
failed = []
results.each do |lane, status|
  summary = File.readlines("tmp/golden-lane-#{lane}.log").grep(/examples?,/).last.to_s.strip
  puts format("lane %d  %-8s %s", lane, status.zero? ? "ok" : "FAILED", summary)
  failed << lane unless status.zero?
end
puts "#{"-" * 60}\n#{elapsed}s wall clock across #{LANES} lane(s)"

if failed.any?
  puts "\nFailures are in tmp/golden-lane-{#{failed.join(",")}}.log"
  puts "Before believing them, re-run the row ALONE — concurrent lanes on one database read as row"
  puts "failures (F88/F89), and a lane that lost its database looks exactly like a broken row."
  exit 1
end
