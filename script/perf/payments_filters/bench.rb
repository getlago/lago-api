# frozen_string_literal: true

# Load test for GET /api/v1/payments across the payments list filters matrix.
#
# HTTP mode (default): N concurrent clients hammer one case for D seconds and
# report p50/p95/p99, throughput and error rate. Run from the host or the api
# container, against a running API:
#
#   PERF_PHASE=baseline PERF_API_URL=http://127.0.0.1:3000 \
#     bundle exec rails runner script/perf/payments_filters/bench.rb
#
# SQL mode (PERF_MODE=sql): the same concurrency, but each client runs the exact
# list + COUNT(*) statements through ActiveRecord connections. That isolates
# database time from Rails/serializer time so the two can be compared.
#
# Env: PERF_PHASE (default baseline), PERF_MODE (http|sql), PERF_CLIENTS (20),
# PERF_DURATION seconds per case (60), PERF_ONLY (regex), PERF_API_URL,
# PERF_CREDENTIALS (default tmp/perf_payments_filters_credentials.json written by
# generate.rb), PERF_ORG_SLUG (perf-big).
#
# Output: script/perf/payments_filters/bench/<phase>.<mode>.json and .md.
# Nothing production-derived is read or written.

raise "This script is only for development" unless Rails.env.development?

require "json"
require "net/http"
require "uri"
require_relative "cases"
ActiveRecord::Base.logger = Logger.new(nil)
HttpLog.configure { |c| c.enabled = false } if defined?(HttpLog) # the client would otherwise log every request body

PHASE = ENV.fetch("PERF_PHASE", "baseline")
MODE = ENV.fetch("PERF_MODE", "http")
CLIENTS = Integer(ENV.fetch("PERF_CLIENTS", 20))
DURATION = Float(ENV.fetch("PERF_DURATION", 60))
ONLY = ENV["PERF_ONLY"] && Regexp.new(ENV["PERF_ONLY"])
API_URL = ENV.fetch("PERF_API_URL", "http://127.0.0.1:3000")
CREDENTIALS = Rails.root.join(ENV.fetch("PERF_CREDENTIALS", "tmp/perf_payments_filters_credentials.json"))

organization = Organization.find_by!(slug: ENV.fetch("PERF_ORG_SLUG", "perf-big"))
api_key = JSON.parse(File.read(CREDENTIALS)).fetch("api_key")
values = PaymentsFiltersPerf::Cases.resolve_values(organization)
cases = PaymentsFiltersPerf::Cases.matrix(values)
cases.select! { |c| c[:name].match?(ONLY) } if ONLY
out_dir = Rails.root.join("script/perf/payments_filters/bench")
FileUtils.mkdir_p(out_dir)

puts "phase=#{PHASE} mode=#{MODE} clients=#{CLIENTS} duration=#{DURATION}s cases=#{cases.size} target=#{(MODE == "http") ? API_URL : ApplicationRecord.connection.current_database}"

def percentile(sorted, pct)
  return nil if sorted.empty?
  sorted[[(sorted.size * pct).ceil - 1, 0].max]
end

# One worker loop: runs `block` until the deadline, records ms per call and errors.
def hammer(clients, duration)
  latencies = Queue.new
  errors = Queue.new
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration
  threads = Array.new(clients) do
    Thread.new do
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          error = yield
          error ? errors << error : latencies << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
        rescue => e
          errors << "#{e.class}: #{e.message[0, 120]}"
        end
      end
    end
  end
  threads.each(&:join)
  [Array.new(latencies.size) { latencies.pop }.sort, Array.new(errors.size) { errors.pop }]
end

http_pool = Hash.new do |h, key|
  uri = URI(API_URL)
  h[key] = Net::HTTP.new(uri.host, uri.port).tap { |c|
    c.use_ssl = uri.scheme == "https"
    c.read_timeout = 60
    c.open_timeout = 5
  }
end

results = []
cases.each do |kase|
  sorted, errors =
    if MODE == "http"
      query = URI.encode_www_form(PaymentsFiltersPerf::Cases.to_query_params(kase))
      path = "/api/v1/payments?#{query}"
      hammer(CLIENTS, DURATION) do
        http = http_pool[Thread.current.object_id]
        response = http.get(path, {"Authorization" => "Bearer #{api_key}", "Accept" => "application/json"})
        (response.code == "200") ? nil : "HTTP #{response.code}: #{response.body.to_s.gsub(/<[^>]+>|\s+/, " ").strip[0, 120]}"
      end
    else
      relation = PaymentsQuery.call(organization:, filters: kase[:filters], search_term: kase[:search_term],
        pagination: {page: kase[:page], limit: 20}).payments
      list_sql = relation.to_sql
      count_sql = relation.except(:offset, :limit, :order, :includes, :preload, :eager_load).select("COUNT(*)").to_sql
      hammer(CLIENTS, DURATION) do
        ApplicationRecord.connection_pool.with_connection do |c|
          c.execute("SET statement_timeout = '30s'")
          c.execute(list_sql)
          c.execute(count_sql)
          nil
        end
      end
    end

  total = sorted.size + errors.size
  entry = {
    name: kase[:name], selective: kase[:selective], page: kase[:page], requests: total,
    rps: (total / DURATION).round(1), errors: errors.size, error_rate: total.zero? ? nil : (errors.size.to_f / total).round(4),
    p50_ms: percentile(sorted, 0.50)&.round(1), p95_ms: percentile(sorted, 0.95)&.round(1), p99_ms: percentile(sorted, 0.99)&.round(1),
    max_ms: sorted.last&.round(1), error_samples: errors.uniq.first(3)
  }
  results << entry
  puts format("%-34s n=%-6d p50 %8.1f  p95 %8.1f  p99 %8.1f  max %8.1f  err %d %s", entry[:name], total, entry[:p50_ms] || 0,
    entry[:p95_ms] || 0, entry[:p99_ms] || 0, entry[:max_ms] || 0, errors.size, errors.uniq.first(1).join)
end

File.write(out_dir.join("#{PHASE}.#{MODE}.json"), JSON.pretty_generate({phase: PHASE, mode: MODE, clients: CLIENTS, duration_s: DURATION,
  generated_at: Time.current.iso8601, target: (MODE == "http") ? API_URL : "sql", cases: results}))
md = "# Load test: #{PHASE} (#{MODE})\n\n#{CLIENTS} concurrent clients, #{DURATION.to_i}s per case, synthetic dataset.\n\n"
md << "| case | selective | requests | req/s | p50 ms | p95 ms | p99 ms | max ms | errors |\n|---|---|---|---|---|---|---|---|---|\n"
results.each { |r| md << "| #{r[:name]} | #{r[:selective]} | #{r[:requests]} | #{r[:rps]} | #{r[:p50_ms]} | #{r[:p95_ms]} | #{r[:p99_ms]} | #{r[:max_ms]} | #{r[:errors]} |\n" }
File.write(out_dir.join("#{PHASE}.#{MODE}.md"), md)
puts "wrote #{out_dir}/#{PHASE}.#{MODE}.{json,md}"
