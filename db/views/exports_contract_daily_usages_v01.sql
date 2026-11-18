SELECT
  du.organization_id,
  du.id AS lago_id,
  du.from_datetime,
  du.to_datetime,
  du.refreshed_at,
  du.usage_date,
  du.usage AS daily_usage,
  du.usage_diff AS daily_usage_diff,
  du.created_at,
  du.updated_at,
  du.customer_id AS lago_customer_id,
  du.contract_id AS lago_contract_id,
  du.external_contract_id,
  du.contract_rate_card_id AS lago_contract_rate_card_id
FROM daily_usages AS du
WHERE du.contract_id IS NOT NULL;
