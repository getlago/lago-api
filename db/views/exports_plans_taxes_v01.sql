SELECT
    pt.organization_id,
    pt.id AS lago_id,
    pt.plan_id AS lago_plan_id,
    pt.catalog_plan_id AS lago_catalog_plan_id,
    pt.tax_id AS lago_tax_id,
    pt.created_at,
    pt.updated_at
FROM plans_taxes AS pt;
