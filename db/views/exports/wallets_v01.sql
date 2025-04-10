SELECT
    w.organization_id,
    w.id AS lago_id,
    w.customer_id AS lago_customer_id,
    CASE w.status
        WHEN 0 THEN 'active'
        WHEN 1 THEN 'terminated'
    END AS status,
    w.balance_currency AS currency,
    w.name,
    w.rate_amount,
    w.credits_balance,
    w.credits_ongoing_balance,
    w.credits_ongoing_usage_balance,
    w.balance_cents,
    w.ongoing_balance_cents,
    w.ongoing_usage_balance_cents,
    w.consumed_credits,
    w.created_at::timestampz::text AS created_at,
    w.updated_at::timestampz::text AS updated_at,
    w.terminated_at::timestampz::text AS terminated_at,
    w.last_balance_sync_at::timestampz::text AS last_balance_sync_at,
    w.last_consumed_credit_at::timestampz::text AS last_consumed_credit_at,
    w.invoice_requires_successful_payment,
FROM wallets AS w
LEFT JOIN customers AS c ON w.customer_id = c.id;
