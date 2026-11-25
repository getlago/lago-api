SELECT
  cp.organization_id,
  cp.id AS lago_id,
  cp.code,
  cp.name,
  cp.invoice_display_name,
  cp.description,
  cp.currency,
  cp.created_at,
  cp.updated_at,
  cp.deleted_at
FROM catalog_plans AS cp;
