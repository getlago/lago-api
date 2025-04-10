SELECT
    t.organization_id,
    t.id AS lago_id,
    t.fee_id AS lago_fee_id,
    t.tax_id AS lago_tax_id,
    t.tax_name,
    t.tax_code,
    t.tax_rate,
    t.tax_description,
    t.amount_cents,
    t.amount_currency,
    t.created_at::timestampz::text AS created_at

FROM fee_taxes AS ft
LEFT JOIN fees AS f ON f.id = ft.fee_id;
