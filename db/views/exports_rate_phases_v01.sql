SELECT
    rp.organization_id,
    rp.id AS lago_id,
    rp.plan_rate_card_id AS lago_plan_rate_card_id,
    rp.contract_rate_card_id AS lago_contract_rate_card_id,
    rp.rate_override_id AS lago_rate_override_id,
    rp.code,
    rp.name,
    rp.position,
    rp.billing_interval_cycle_count,
    rp.created_at,
    rp.updated_at,
    rp.deleted_at
FROM rate_phases AS rp;
