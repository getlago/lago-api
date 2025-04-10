SELECT
  p.organization_id,
  p.id AS lago_id,
  p.name,
  p.invoice_display_name,
  p.created_at::timestampz::text AS created_at,
  p.code,
  CASE p.interval
    WHEN 0 then 'weekly',
    WHEN 1 then 'monthly',
    WHEN 2 then 'yearly',
    WHEN 3 then 'quarterly'
  END AS interval,
  p.description,
  p.amount_cents,
  p.amount_currency,
  p.trial_period,
  p.pay_in_advance,
  p.bill_charges_monthly,
  p.parent_id
FROM plans AS p
WHERE p.deleted_at IS NULL;
