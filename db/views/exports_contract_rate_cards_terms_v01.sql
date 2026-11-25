SELECT
  crct.organization_id,
  crct.id AS lago_id,
  crct.contract_rate_card_id AS lago_contract_rate_card_id,
  crct.units,
  crct.effective_date,
  crct.application_timing::text AS application_timing,
  crct.created_at,
  crct.updated_at
FROM contract_rate_cards_terms AS crct;
