# frozen_string_literal: true

# Builds a production-shaped synthetic dataset for the payments list filters
# performance work. Rails runner, development only, throwaway database only.
#
#   DATABASE_URL=postgresql://lago:changeme@db:5432/lago_perf \
#     bundle exec rails runner script/perf/payments_filters/generate.rb
#
# Everything here is synthetic. The skews are illustrative round numbers
# (for example "92 % succeeded"), not production figures. Re-tune them through
# the env knobs below when real distributions are known; keep production values
# out of this file.
#
# Knobs (env):
#   PERF_BIG_PAYMENTS  payments in the big organization        (default 5_000_000)
#   PERF_SMALL_ORGS    number of other organizations            (default 50)
#   PERF_SMALL_MIN     smallest other organization, payments    (default 1_000)
#   PERF_SMALL_MAX     largest other organization, payments     (default 200_000)
#   PERF_BIG_CUSTOMERS customers in the big organization        (default 50_000)
#   PERF_MONTHS        created_at spread, months back from now  (default 24)
#   PERF_SEED          seed for Ruby and PostgreSQL randomness  (default 42)
#   PERF_ALLOW_DB=1    run against a database whose name has no "perf" in it
#
# Dimension tables (organizations, providers) go through the factories so the
# rows look like the app made them. Fact tables (customers, invoices,
# payment_requests, payments, receipts, methods) are set-based SQL over
# generate_series(): minutes instead of hours, same determinism.
#
# Non-unique indexes on the fact tables are dropped before the load and
# rebuilt afterwards (timed, logged). That keeps the load fast and leaves
# compact indexes, which is what a vacuumed production table looks like.

raise "This generator is only for development" unless Rails.env.development?

require "factory_bot_rails"
require "json"

FactoryBot.find_definitions if FactoryBot.factories.none?
ActiveJob::Base.queue_adapter = :test
ActiveRecord::Base.logger = Logger.new(nil) # keep stdout readable; SQL is in the saved plans

BIG_PAYMENTS = Integer(ENV.fetch("PERF_BIG_PAYMENTS", 5_000_000))
SMALL_ORGS = Integer(ENV.fetch("PERF_SMALL_ORGS", 50))
SMALL_MIN = Integer(ENV.fetch("PERF_SMALL_MIN", 1_000))
SMALL_MAX = Integer(ENV.fetch("PERF_SMALL_MAX", 200_000))
BIG_CUSTOMERS = Integer(ENV.fetch("PERF_BIG_CUSTOMERS", 50_000))
MONTHS = Integer(ENV.fetch("PERF_MONTHS", 24))
SEED = Integer(ENV.fetch("PERF_SEED", 42))
FIRST_ATTEMPT_SHARE = 0.9 # the remaining 10 % are failed retries on an existing payable

FACT_TABLES = %w[payments payment_receipts invoices payment_requests invoices_payment_requests payment_methods customers].freeze

conn = ApplicationRecord.connection
db_name = conn.current_database
unless db_name.include?("perf") || ENV["PERF_ALLOW_DB"] == "1"
  abort "Refusing to run against #{db_name.inspect}: the database name must contain \"perf\" (or set PERF_ALLOW_DB=1)."
end

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
elapsed = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) - started }
log = ->(msg) { puts format("[%7.1fs] %s", elapsed.call, msg) }

run = lambda do |label, sql|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = conn.execute(sql)
  log.call(format("%-52s %8.1fs%s", label, Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0,
    (result.respond_to?(:cmd_tuples) && result.cmd_tuples.positive?) ? " (#{result.cmd_tuples} rows)" : ""))
  result
end

log.call("database=#{db_name} big=#{BIG_PAYMENTS} small_orgs=#{SMALL_ORGS} seed=#{SEED} months=#{MONTHS}")

# --- 1. Reset -----------------------------------------------------------------
run.call("truncate organizations cascade", "TRUNCATE TABLE organizations CASCADE")
run.call("truncate users cascade", "TRUNCATE TABLE users CASCADE")
conn.execute("DROP TABLE IF EXISTS perf_orgs, perf_customers, perf_rows, perf_facts")

# --- 2. Organizations and providers (factories) ------------------------------
rng = Random.new(SEED)
orgs = []

big_org = FactoryBot.create(:organization, name: "Perf Big Org", slug: "perf-big", webhook_url: nil, document_number_prefix: "PERFBIG")
orgs << {org: big_org, idx: 0, n_payments: BIG_PAYMENTS, n_customers: BIG_CUSTOMERS}
SMALL_ORGS.times do |i|
  size = (SMALL_MIN * ((SMALL_MAX.to_f / SMALL_MIN)**rng.rand)).round
  org = FactoryBot.create(:organization, name: "Perf Org #{i + 1}", slug: "perf-#{i + 1}", webhook_url: nil, document_number_prefix: "PERF#{i + 1}")
  orgs << {org:, idx: i + 1, n_payments: size, n_customers: [size / 50, 10].max}
end
log.call("created #{orgs.size} organizations via factories")

orgs.each do |entry|
  org = entry[:org]
  entry[:stripe] = FactoryBot.create(:stripe_provider, organization: org, code: "perf_stripe", name: "Perf Stripe")
  # Every third organization also has a second provider type so provider_type is a real filter.
  entry[:second] =
    if entry[:idx] == 0 || entry[:idx] % 3 == 0
      FactoryBot.create(:gocardless_provider, organization: org, code: "perf_gocardless", name: "Perf GoCardless")
    elsif entry[:idx] % 3 == 1
      FactoryBot.create(:adyen_provider, organization: org, code: "perf_adyen", name: "Perf Adyen")
    end
end
log.call("created payment providers via factories")

conn.execute(<<~SQL)
  CREATE UNLOGGED TABLE perf_orgs (
    idx int PRIMARY KEY, organization_id uuid, billing_entity_id uuid, prefix text,
    n_payments int, n_first int, n_customers int, stripe_id uuid, second_id uuid
  )
SQL
values = orgs.map do |e|
  be = e[:org].default_billing_entity
  "(#{e[:idx]}, #{conn.quote(e[:org].id)}, #{conn.quote(be.id)}, #{conn.quote(be.document_number_prefix)}, #{e[:n_payments]}, " \
    "#{(e[:n_payments] * FIRST_ATTEMPT_SHARE).floor}, #{e[:n_customers]}, #{conn.quote(e[:stripe].id)}, #{conn.quote(e[:second]&.id)})"
end
conn.execute("INSERT INTO perf_orgs VALUES #{values.join(", ")}")

# --- 3. Drop non-unique indexes on the fact tables (rebuilt at the end) ------
saved_indexes = conn.select_rows(<<~SQL)
  SELECT tablename, indexname, indexdef FROM pg_indexes
  WHERE schemaname = 'public' AND tablename IN (#{FACT_TABLES.map { |t| "'#{t}'" }.join(", ")})
    AND indexdef NOT LIKE 'CREATE UNIQUE INDEX%'
  ORDER BY tablename, indexname
SQL
saved_indexes.each { |(_table, name, _def)| conn.execute("DROP INDEX IF EXISTS #{conn.quote_table_name(name)}") }
log.call("dropped #{saved_indexes.size} non-unique indexes for the bulk load")

# --- 4. Customers and payment methods -----------------------------------------
run.call("insert customers", <<~SQL)
  INSERT INTO customers (id, organization_id, billing_entity_id, external_id, name, slug, sequential_id, currency, created_at, updated_at)
  SELECT gen_random_uuid(), o.organization_id, o.billing_entity_id,
         'perf-cust-' || o.idx || '-' || c, 'Perf Customer ' || o.idx || '-' || c,
         o.prefix || '-' || lpad(c::text, 3, '0'), c, 'EUR',
         now() - interval '1 month' * #{MONTHS}, now()
  FROM perf_orgs o CROSS JOIN LATERAL generate_series(1, o.n_customers) AS c
SQL

conn.execute("SELECT setseed(#{(SEED % 1000) / 1000.0})")
# One saved payment method per customer, on the Stripe provider. bacs_debit and
# customer_balance exist only here, never in the payments jsonb: they exercise
# the payment_methods fallback branch of the payment_method_type filter.
run.call("insert payment_methods", <<~SQL)
  INSERT INTO payment_methods (id, organization_id, customer_id, payment_provider_id, provider_method_id, provider_method_type, is_default, created_at, updated_at)
  SELECT gen_random_uuid(), s.organization_id, s.id, s.stripe_id, 'pm_perf_' || s.sequential_id || '_' || s.idx,
         CASE WHEN s.r < 0.80 THEN 'card' WHEN s.r < 0.92 THEN 'sepa_debit' WHEN s.r < 0.96 THEN 'link'
              WHEN s.r < 0.985 THEN 'us_bank_account' WHEN s.r < 0.995 THEN 'bacs_debit' ELSE 'customer_balance' END,
         true, s.created_at, s.created_at
  FROM (SELECT c.organization_id, c.id, c.sequential_id, c.created_at, o.stripe_id, o.idx, random() AS r
        FROM customers c JOIN perf_orgs o ON o.organization_id = c.organization_id) s
SQL

run.call("build perf_customers", <<~SQL)
  CREATE UNLOGGED TABLE perf_customers AS
  SELECT c.organization_id, c.sequential_id AS cidx, c.id AS customer_id, c.slug, pm.id AS payment_method_id
  FROM customers c LEFT JOIN payment_methods pm ON pm.customer_id = c.id
SQL
conn.execute("CREATE INDEX ON perf_customers (organization_id, cidx)")

# --- 5. Per-payment random draws ----------------------------------------------
run.call("draw perf_rows", <<~SQL)
  CREATE UNLOGGED TABLE perf_rows AS
  SELECT o.idx AS org_idx, o.organization_id, o.billing_entity_id, o.prefix, o.stripe_id, o.second_id,
         o.n_customers, o.n_first, n,
         gen_random_uuid() AS payment_id,
         random() AS r_status, random() AS r_cur, random() AS r_type, random() AS r_method, random() AS r_pm,
         random() AS r_receipt, random() AS r_request, random() AS r_inv_status, random() AS r_amt1,
         random() AS r_amt2, random() AS r_big, random() AS r_cust, random() AS r_time
  FROM perf_orgs o CROSS JOIN LATERAL generate_series(1, o.n_payments) AS n
SQL
conn.execute("CREATE INDEX ON perf_rows (organization_id, n)")

# First attempts carry their own payable; retries (n > n_first) reuse the
# payable, customer and currency of row n - n_first and are always failed, so
# the partial unique index on pending/processing provider payments holds.
run.call("derive perf_facts (first attempts)", <<~SQL)
  CREATE UNLOGGED TABLE perf_facts AS
  SELECT b.org_idx, b.organization_id, b.billing_entity_id, b.prefix, b.n, b.payment_id, true AS first_attempt,
         gen_random_uuid() AS invoice_id,
         CASE WHEN b.r_request < 0.05 THEN gen_random_uuid() END AS payment_request_id,
         b.r_request < 0.05 AS is_request,
         CASE WHEN b.r_request < 0.025 THEN 1 ELSE 2 END AS extra_invoices,
         1 + floor(power(b.r_cust, 3) * b.n_customers)::int AS cidx,
         now() - (interval '1 month' * #{MONTHS}) * power(b.r_time, 0.6) AS created_at,
         CASE WHEN b.r_cur < 0.95 THEN 'EUR' WHEN b.r_cur < 0.99 THEN 'USD' ELSE 'GBP' END AS currency,
         CASE WHEN b.r_status < 0.92 THEN 'succeeded' WHEN b.r_status < 0.97 THEN 'failed'
              WHEN b.r_status < 0.99 THEN 'pending' ELSE 'processing' END AS status,
         CASE WHEN b.r_type < 0.05 THEN 'manual' ELSE 'provider' END AS payment_type,
         CASE WHEN b.r_type < 0.05 THEN NULL WHEN b.r_type < 0.85 THEN b.stripe_id ELSE COALESCE(b.second_id, b.stripe_id) END AS provider_id,
         (b.r_type >= 0.05 AND (b.r_type < 0.85 OR b.second_id IS NULL)) AS is_stripe,
         CASE WHEN b.r_method < 0.85 THEN 'card' WHEN b.r_method < 0.95 THEN 'sepa_debit' WHEN b.r_method < 0.98 THEN 'link'
              WHEN b.r_method < 0.995 THEN 'us_bank_account' WHEN b.r_method < 0.999 THEN 'boleto' ELSE 'crypto' END AS method_type,
         b.r_pm < 0.9 AS pm_in_json,
         CASE WHEN b.r_inv_status < 0.93 THEN 1 WHEN b.r_inv_status < 0.95 THEN 0 WHEN b.r_inv_status < 0.97 THEN 2
              WHEN b.r_inv_status < 0.98 THEN 4 WHEN b.r_inv_status < 0.99 THEN 7 ELSE 5 END AS invoice_status,
         CASE WHEN b.r_big < 0.0001 THEN 2147483648::bigint + floor(b.r_amt1 * 1e12)::bigint
              ELSE greatest(1, round(exp(8.5 + 1.2 * sqrt(-2 * ln(greatest(b.r_amt1, 1e-12))) * cos(2 * pi() * b.r_amt2))))::bigint END AS amount_cents,
         b.r_receipt
  FROM perf_rows b
  WHERE b.n <= b.n_first
SQL
conn.execute("CREATE INDEX ON perf_facts (organization_id, n)")

run.call("derive perf_facts (retries)", <<~SQL)
  INSERT INTO perf_facts
  SELECT b.org_idx, b.organization_id, b.billing_entity_id, b.prefix, b.n, b.payment_id, false,
         f.invoice_id, f.payment_request_id, f.is_request, 0, f.cidx,
         f.created_at - interval '1 day' * (1 + floor(b.r_time * 3)),
         f.currency, 'failed', f.payment_type, f.provider_id, f.is_stripe, f.method_type, f.pm_in_json,
         f.invoice_status, f.amount_cents, 1.0
  FROM perf_rows b
  JOIN perf_facts f ON f.organization_id = b.organization_id AND f.n = b.n - b.n_first
  WHERE b.n > b.n_first
SQL
conn.execute("DROP TABLE perf_rows")

# --- 6. Payables -------------------------------------------------------------
run.call("insert invoices", <<~SQL)
  INSERT INTO invoices (id, organization_id, billing_entity_id, customer_id, number, status, payment_status, currency,
                        total_amount_cents, issuing_date, payment_due_date, created_at, updated_at, organization_sequential_id)
  SELECT f.invoice_id, f.organization_id, f.billing_entity_id, c.customer_id,
         f.prefix || '-' || to_char(f.created_at, 'YYYYMM') || '-' || lpad(f.n::text, 9, '0'),
         f.invoice_status, CASE WHEN f.status = 'succeeded' THEN 1 ELSE 0 END, f.currency,
         f.amount_cents, f.created_at::date, f.created_at::date + 30, f.created_at - interval '1 hour', f.created_at, f.n
  FROM perf_facts f JOIN perf_customers c ON c.organization_id = f.organization_id AND c.cidx = f.cidx
  WHERE f.first_attempt
SQL

run.call("insert payment_requests", <<~SQL)
  INSERT INTO payment_requests (id, organization_id, customer_id, amount_cents, amount_currency, payment_status, email, created_at, updated_at)
  SELECT f.payment_request_id, f.organization_id, c.customer_id, f.amount_cents, f.currency,
         CASE WHEN f.status = 'succeeded' THEN 1 WHEN f.status = 'failed' THEN 2 ELSE 0 END,
         'perf@example.com', f.created_at - interval '1 hour', f.created_at
  FROM perf_facts f JOIN perf_customers c ON c.organization_id = f.organization_id AND c.cidx = f.cidx
  WHERE f.first_attempt AND f.is_request
SQL

# A payment request covers its own invoice plus the next one or two invoices of the same organization.
run.call("insert invoices_payment_requests", <<~SQL)
  INSERT INTO invoices_payment_requests (invoice_id, payment_request_id, organization_id, created_at, updated_at)
  SELECT g.invoice_id, f.payment_request_id, f.organization_id, f.created_at - interval '1 hour', f.created_at
  FROM perf_facts f
  JOIN perf_facts g ON g.organization_id = f.organization_id AND g.first_attempt
                   AND g.n BETWEEN f.n AND f.n + f.extra_invoices
  WHERE f.first_attempt AND f.is_request
SQL

# --- 7. Payments and receipts -------------------------------------------------
run.call("insert payments", <<~SQL)
  INSERT INTO payments (id, organization_id, customer_id, payable_type, payable_id, amount_cents, amount_currency, status,
                        payable_payment_status, payment_type, reference, provider_payment_id, payment_provider_id,
                        payment_method_id, provider_payment_method_data, created_at, updated_at)
  SELECT f.payment_id, f.organization_id, c.customer_id,
         CASE WHEN f.is_request THEN 'PaymentRequest' ELSE 'Invoice' END,
         CASE WHEN f.is_request THEN f.payment_request_id ELSE f.invoice_id END,
         f.amount_cents, f.currency, f.status, f.status::payment_payable_payment_status, f.payment_type::payment_type,
         CASE WHEN f.payment_type = 'manual' THEN 'Bank transfer ' || f.n END,
         CASE WHEN f.payment_type = 'provider' THEN 'pi_perf_' || f.org_idx || '_' || f.n END,
         f.provider_id,
         CASE WHEN f.payment_type = 'provider' THEN c.payment_method_id END,
         CASE WHEN f.is_stripe AND f.pm_in_json THEN jsonb_build_object('type', f.method_type, 'last4', '4242', 'brand', 'visa')
              ELSE '{}'::jsonb END,
         f.created_at, f.created_at
  FROM perf_facts f JOIN perf_customers c ON c.organization_id = f.organization_id AND c.cidx = f.cidx
SQL

conn.execute("ALTER TABLE payment_receipts DISABLE TRIGGER before_payment_receipt_insert")
begin
  # Receipts on ~60 % of succeeded payments, numbered the way the trigger does it.
  run.call("insert payment_receipts", <<~SQL)
    INSERT INTO payment_receipts (id, number, payment_id, organization_id, billing_entity_id, created_at, updated_at)
    SELECT gen_random_uuid(),
           c.slug || '-RCPT-' || lpad((row_number() OVER (PARTITION BY c.customer_id ORDER BY f.created_at, f.n))::text, 6, '0'),
           f.payment_id, f.organization_id, f.billing_entity_id, f.created_at + interval '1 minute', f.created_at + interval '1 minute'
    FROM perf_facts f JOIN perf_customers c ON c.organization_id = f.organization_id AND c.cidx = f.cidx
    WHERE f.status = 'succeeded' AND f.r_receipt < 0.65
  SQL
ensure
  conn.execute("ALTER TABLE payment_receipts ENABLE TRIGGER before_payment_receipt_insert")
end
run.call("sync customers.payment_receipt_counter", <<~SQL)
  UPDATE customers c SET payment_receipt_counter = r.n
  FROM (SELECT p.customer_id, count(*) AS n FROM payment_receipts pr JOIN payments p ON p.id = pr.payment_id GROUP BY p.customer_id) r
  WHERE r.customer_id = c.id
SQL

conn.execute("DROP TABLE perf_facts, perf_customers, perf_orgs")

# --- 8. Rebuild indexes, vacuum, analyze -------------------------------------
index_times = saved_indexes.map do |(table, name, definition)|
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  conn.execute(definition)
  secs = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  log.call(format("rebuilt %-62s %8.1fs", name, secs))
  [table, name, secs]
end

FACT_TABLES.each { |t| run.call("vacuum analyze #{t}", "VACUUM (ANALYZE) #{t}") }
run.call("analyze payment_providers, organizations", "ANALYZE payment_providers; ANALYZE organizations; ANALYZE billing_entities")

# --- 9. Report ---------------------------------------------------------------
puts
puts "Row counts:"
FACT_TABLES.each do |t|
  puts format("  %-28s %12s", t, conn.select_value("SELECT count(*) FROM #{t}").to_s)
end
puts format("  %-28s %12s", "database size", conn.select_value("SELECT pg_size_pretty(pg_database_size(current_database()))"))
puts format("  %-28s %12s", "payments total (heap+idx)", conn.select_value("SELECT pg_size_pretty(pg_total_relation_size('payments'))"))
puts format("  %-28s %12s", "invoices total (heap+idx)", conn.select_value("SELECT pg_size_pretty(pg_total_relation_size('invoices'))"))

puts
puts "Big organization (#{big_org.slug}) distributions:"
[
  ["payable_payment_status", "SELECT payable_payment_status::text, count(*) FROM payments WHERE organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["amount_currency", "SELECT amount_currency, count(*) FROM payments WHERE organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["payment_type", "SELECT payment_type::text, count(*) FROM payments WHERE organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["payable_type", "SELECT payable_type, count(*) FROM payments WHERE organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["provider type", "SELECT pp.type, count(*) FROM payments p LEFT JOIN payment_providers pp ON pp.id = p.payment_provider_id WHERE p.organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["jsonb method type", "SELECT coalesce(provider_payment_method_data->>'type', '(none)'), count(*) FROM payments WHERE organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC"],
  ["heaviest customers", "SELECT c.external_id, count(*) FROM payments p JOIN customers c ON c.id = p.customer_id WHERE p.organization_id = '#{big_org.id}' GROUP BY 1 ORDER BY 2 DESC LIMIT 3"]
].each do |label, sql|
  puts "  #{label}: " + conn.select_rows(sql).map { |k, v| "#{k}=#{v}" }.join(", ")
end

puts
puts "Index rebuild times on the loaded dataset (reference for CREATE INDEX cost):"
index_times.select { |(table, _, _)| table == "payments" }.each { |(_, name, secs)| puts format("  %-62s %6.1fs", name, secs) }

credentials_path = Rails.root.join("tmp/perf_payments_filters_credentials.json")
File.write(credentials_path, JSON.pretty_generate({
  organization_id: big_org.id, organization_slug: big_org.slug,
  api_key: big_org.api_keys.first.value, database: db_name, generated_at: Time.current.iso8601,
  params: {big_payments: BIG_PAYMENTS, small_orgs: SMALL_ORGS, seed: SEED, months: MONTHS}
}), perm: 0o600)
puts
log.call("done. Credentials for bench.rb: #{credentials_path} (local only, never commit)")
