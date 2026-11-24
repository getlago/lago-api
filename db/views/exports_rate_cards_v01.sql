SELECT
    rc.organization_id,
    rc.id AS lago_id,
    rc.product_id AS lago_product_id,
    rc.product_filter_id AS lago_product_filter_id,
    rc.code,
    rc.name,
    rc.description,
    rc.currency,
    rc.billing_timing::text AS billing_timing,
    rc.proration,
    rc.display_on_invoice,
    rc.regroup_paid_fees::text AS regroup_paid_fees,
    rc.applied_pricing_unit_code,
    rc.created_at,
    rc.updated_at,
    rc.deleted_at
FROM rate_cards AS rc;
