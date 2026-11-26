SELECT
  pc.organization_id,
  pc.id AS lago_id,
  pc.code,
  pc.name,
  pc.description,
  pc.invoice_display_name,
  pc.created_at,
  pc.updated_at,
  pc.deleted_at
FROM product_categories AS pc;
