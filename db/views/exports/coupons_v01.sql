SELECT
    cp.organization_id,
    cp.id AS lago_id,
    cp.name,
    cp.code,
    cp.description,
    CASE cp.coupon_type
        WHEN 0 THEN 'fixed_amount'
        WHEN 1 THEN 'percentage'
    END AS coupon_type,
    cp.amount_cents,
    cp.amount_currency,
    cp.percentage_rate,
    cp.frequency,
    cp.frequency_duration,
    cp.reusable,
    cp.limited_plans,
    cp.limited_billable_metrics,
    json_agg(
        SELECT cpt.plan_id
        FROM coupon_targets AS cpt
        WHERE cpt.coupon_id = cp.id
        AND cpt.plan_id IS NOT NULL
    ) AS lago_plan_ids,
    json_agg(
        SELECT cpt.billable_metric_id
        FROM coupon_targets AS cpt
        WHERE cpt.coupon_id = cp.id
        AND cpt.billable_metric_id IS NOT NULL
    ) AS lago_billable_metrics_ids,
    cp.created_at::timestampz::text AS created_at,
    cp.expiration::timestampz::text AS expiration,
    cp.expiration_at::timestampz::text AS expiration_at,
    cp.terminated_at::timestampz::text AS terminated_at
FROM coupons AS cp;
