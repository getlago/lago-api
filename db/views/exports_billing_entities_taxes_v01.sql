SELECT
    bet.organization_id,
    bet.id AS lago_id,
    bet.billing_entity_id AS lago_billing_entity_id,
    bet.tax_id AS lago_tax_id,
    bet.created_at,
    bet.updated_at
FROM billing_entities_taxes AS bet;
