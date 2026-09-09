-- Phase 0: production scale for the payments list filters performance work.
-- Read-only. Run on a READ REPLICA with psql. Results are confidential:
-- paste them into the internal performance document only, never into a PR,
-- a commit, or this repository.
--
--   psql "$REPLICA_URL" -v big="'<organization_id of the largest org>'" -f phase0.sql
--
-- Run the first block without :big, pick the top organization_id from the
-- second query, then rerun with -v big=... for the per-column blocks.

\timing on
\pset pager off

-- 0. Engine version and the session ceilings the app runs under.
SELECT version();
SHOW statement_timeout;
SHOW lock_timeout;
-- Planner cost parameters: the synthetic runs showed that whether the planner picks a
-- (organization_id, <column>) index for a common value depends on these.
SHOW random_page_cost;
SHOW seq_page_cost;
SHOW effective_cache_size;
SHOW work_mem;
SHOW shared_buffers;

-- 1. Size and distribution.
SELECT count(*) AS payments FROM payments;
SELECT organization_id, count(*) FROM payments GROUP BY 1 ORDER BY 2 DESC LIMIT 10;
SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY c) AS p50_org,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY c) AS p99_org,
       max(c) AS max_org, count(*) AS orgs
  FROM (SELECT count(*) c FROM payments GROUP BY organization_id) t;
SELECT count(*) AS payment_receipts FROM payment_receipts;
SELECT count(*) AS invoices FROM invoices;
SELECT count(*) AS invoices_payment_requests FROM invoices_payment_requests;
SELECT count(*) AS payment_requests FROM payment_requests;
SELECT count(*) AS payment_methods FROM payment_methods;

-- 2. Per-column selectivity on the biggest org (:big).
SELECT payable_payment_status, count(*) FROM payments WHERE organization_id = :big GROUP BY 1 ORDER BY 2 DESC;
SELECT amount_currency, count(*) FROM payments WHERE organization_id = :big GROUP BY 1 ORDER BY 2 DESC;
SELECT payment_type, payable_type, count(*) FROM payments WHERE organization_id = :big GROUP BY 1,2 ORDER BY 3 DESC;
SELECT provider_payment_method_data->>'type' AS method_type, count(*) FROM payments WHERE organization_id = :big GROUP BY 1 ORDER BY 2 DESC;
SELECT count(*) FILTER (WHERE provider_payment_method_data = '{}'::jsonb) AS empty_pm_data,
       count(*) FILTER (WHERE payment_method_id IS NOT NULL) AS with_payment_method_id,
       count(*) AS total
  FROM payments WHERE organization_id = :big;
SELECT pm.provider_method_type, count(*)
  FROM payments p JOIN payment_methods pm ON pm.id = p.payment_method_id
 WHERE p.organization_id = :big AND (p.provider_payment_method_data->>'type') IS NULL
 GROUP BY 1 ORDER BY 2 DESC;
SELECT payment_provider_id, count(*) FROM payments WHERE organization_id = :big GROUP BY 1 ORDER BY 2 DESC;
SELECT pp.type, count(*) FROM payments p LEFT JOIN payment_providers pp ON pp.id = p.payment_provider_id
 WHERE p.organization_id = :big GROUP BY 1 ORDER BY 2 DESC;
SELECT count(*) AS customers, max(c) AS max_payments_per_customer,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY c) AS p99_payments_per_customer
  FROM (SELECT customer_id, count(*) c FROM payments WHERE organization_id = :big GROUP BY 1) t;
SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY amount_cents) AS p50_amount,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY amount_cents) AS p99_amount,
       max(amount_cents) AS max_amount,
       count(*) FILTER (WHERE amount_cents > 2147483647) AS above_int32
  FROM payments WHERE organization_id = :big;
SELECT date_trunc('month', created_at) AS month, count(*) FROM payments WHERE organization_id = :big GROUP BY 1 ORDER BY 1;
SELECT count(*) AS receipts_big_org,
       count(*) FILTER (WHERE number <> upper(number)) AS receipts_with_lowercase
  FROM payment_receipts WHERE organization_id = :big;
SELECT count(*) AS invoices_big_org,
       count(*) FILTER (WHERE number <> upper(number)) AS invoices_with_lowercase,
       count(*) FILTER (WHERE status NOT IN (0,1,2,4,7)) AS invisible_status
  FROM invoices WHERE organization_id = :big;
SELECT count(*) AS payments_via_payment_request,
       avg(n)::numeric(6,2) AS avg_invoices_per_request
  FROM (SELECT pr.id, count(ipr.invoice_id) n
          FROM payment_requests pr JOIN invoices_payment_requests ipr ON ipr.payment_request_id = pr.id
         WHERE pr.organization_id = :big GROUP BY pr.id) t;

-- 3. Planner statistics as it sees them.
SELECT attname, n_distinct, most_common_vals, most_common_freqs, correlation
  FROM pg_stats
 WHERE tablename = 'payments'
   AND attname IN ('organization_id','payable_payment_status','amount_currency','payment_type','payable_type','amount_cents','created_at','payment_provider_id','customer_id');

-- 4. Write rate and index usage (to price every new index).
SELECT n_tup_ins, n_tup_upd, n_tup_hot_upd, n_tup_del, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
  FROM pg_stat_user_tables WHERE relname = 'payments';
SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
  FROM pg_stat_user_indexes WHERE relname = 'payments' ORDER BY idx_scan, indexrelname;
SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
  FROM pg_stat_user_indexes WHERE relname IN ('payment_receipts','invoices_payment_requests') ORDER BY relname, idx_scan;
SELECT pg_size_pretty(pg_total_relation_size('payments')) AS payments_total,
       pg_size_pretty(pg_relation_size('payments')) AS payments_heap,
       pg_size_pretty(pg_total_relation_size('invoices')) AS invoices_total,
       pg_size_pretty(pg_total_relation_size('payment_receipts')) AS receipts_total;
SELECT stats_reset FROM pg_stat_database WHERE datname = current_database();
