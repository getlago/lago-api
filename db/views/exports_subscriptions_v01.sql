SELECT
    c.organization_id,
    s.id AS lago_id,
    s.external_id,
    s.customer_id AS lago_customer_id,
    s.name,
    s.plan_id AS lago_plan_id,
    CASE s.status
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'active'
        WHEN 2 THEN 'terminated'
        WHEN 3 THEN 'canceled'
    END AS status,
    CASE s.billing_time
        WHEN 0 THEN 'calendar'
        WHEN 1 THEN 'anniversary'
    END AS billing_time,
    s.subscription_at::timestampz::text AS subscription_at,
    s.started_at::timestampz::text AS started_at,
    s.trial_ended_at::timestampz::text AS trial_ended_at,
    s.ending_at::timestampz::text AS ending_at,
    s.terminated_at::timestampz::text AS terminated_at,
    s.canceled_at::timestampz::text AS canceled_at,
    s.created_at::timestampz::text AS created_at,
    s.updated_at::timestampz::text AS updated_at,
    json_agg(
        SELECT ns.id
        FROM subscriptions AS ns
        WHERE ns.previous_subscription_id = s.id
    ) AS lago_next_subscriptions_id,
    s.previous_subscription_id AS lago_previous_subscription_id,
    
FROM subscriptions AS s
LEFT JOIN customers AS c ON s.customer_id = c.id;
