SELECT
    c.organization_id,
    cn.id AS lago_id,
    cnt.tax_id AS lago_tax_id,
    cnt.credit_note_id AS lago_credit_note_id,
    cnt.tax_name,
    cnt.tax_code,
    cnt.tax_rate,
    cnt.tax_description,
    cnt.base_amount_cents,
    cnt.amount_cents,
    cnt.amount_currency,
    cnt.created_at::timestampz::text AS created_at
FROM credit_note_taxes AS cnt
LEFT JOIN credit_notes AS cn ON cn.id = credit_note_taxes.credit_note_id
LEFT JOIN customers AS c ON c.id = cn.customer_id;
