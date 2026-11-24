SELECT
    ro.organization_id,
    ro.id AS lago_id,
    ro.rate_model::text AS rate_model,
    ro.rate_properties,
    ro.min_amount_cents,
    ro.billing_interval_count,
    ro.billing_interval_unit::text AS billing_interval_unit,
    ro.pricing_unit_conversion_rate,
    ro.created_at,
    ro.updated_at,
    ro.deleted_at
FROM rate_overrides AS ro;
