SELECT
    rcr.organization_id,
    rcr.id AS lago_id,
    rcr.rate_card_id AS lago_rate_card_id,
    rcr.code,
    rcr.effective_from,
    rcr.rate_model::text AS rate_model,
    rcr.rate_properties,
    rcr.min_amount_cents,
    rcr.billing_interval_count,
    rcr.billing_interval_unit::text AS billing_interval_unit,
    rcr.applied_pricing_unit_conversion_rate,
    rcr.created_at,
    rcr.updated_at,
    rcr.deleted_at
FROM rate_card_rates AS rcr;
