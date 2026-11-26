SELECT
  pf.organization_id,
  pf.id AS lago_id,
  pf.product_id AS lago_product_id,
  pf.code,
  pf.name,
  pf.description,
  pf.invoice_display_name,
  pf.created_at,
  -- Values live in their own table: a change to them must move the filter's updated_at too.
  GREATEST(pf.updated_at, pfv_stats.updated_at) AS updated_at,
  pf.deleted_at,
  COALESCE(pfv_stats.kept_values, '[]'::json) AS filter_values
FROM product_filters AS pf
LEFT JOIN LATERAL (
  SELECT
    MAX(pfv.updated_at) AS updated_at,
    json_agg(
      json_build_object('key', bmf.key, 'value', pfv.value)
      ORDER BY pfv.created_at, pfv.id
    ) FILTER (WHERE pfv.deleted_at IS NULL) AS kept_values
  FROM product_filter_values AS pfv
  INNER JOIN billable_metric_filters AS bmf ON bmf.id = pfv.billable_metric_filter_id
  WHERE pfv.product_filter_id = pf.id
) AS pfv_stats ON TRUE;
