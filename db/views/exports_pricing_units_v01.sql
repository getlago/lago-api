SELECT
  pu.organization_id,
  pu.id AS lago_id,
  pu.code,
  pu.name,
  pu.short_name,
  pu.description,
  pu.created_at,
  pu.updated_at
FROM pricing_units AS pu;
