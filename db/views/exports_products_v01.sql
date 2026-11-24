SELECT
  p.organization_id,
  p.id AS lago_id,
  p.product_category_id AS lago_product_category_id,
  p.billable_metric_id AS lago_billable_metric_id,
  p.add_on_id AS lago_add_on_id,
  p.charge_id AS lago_charge_id,
  p.product_type::text AS product_type,
  p.code,
  p.name,
  p.invoice_display_name,
  p.description,
  p.created_at,
  p.updated_at,
  p.deleted_at
FROM products AS p;
