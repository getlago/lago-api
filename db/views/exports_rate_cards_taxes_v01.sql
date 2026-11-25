SELECT
    rct.organization_id,
    rct.id AS lago_id,
    rct.rate_card_id AS lago_rate_card_id,
    rct.tax_id AS lago_tax_id,
    rct.created_at,
    rct.updated_at
FROM rate_cards_taxes AS rct;
