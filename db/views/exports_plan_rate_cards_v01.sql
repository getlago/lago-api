SELECT
  prc.organization_id,
  prc.id AS lago_id,
  prc.catalog_plan_id AS lago_catalog_plan_id,
  prc.rate_card_id AS lago_rate_card_id,
  prc.units,
  prc.created_at,
  prc.updated_at,
  prc.deleted_at
FROM plan_rate_cards AS prc;
