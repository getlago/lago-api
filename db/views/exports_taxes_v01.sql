SELECT
    tx.organization_id,
    tx.id AS lago_id,
    tx.name,
    tx.code,
    tx.rate,
    tx.description,
    tx.applied_to_organization,
    tx.created_at::timestamptz::text AS created_at
FROM taxes AS tx;
