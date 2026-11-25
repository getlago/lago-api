SELECT
    ct.organization_id,
    ct.id AS lago_id,
    ct.customer_id AS lago_customer_id,
    ct.tax_id AS lago_tax_id,
    ct.created_at,
    ct.updated_at
FROM customers_taxes AS ct;
