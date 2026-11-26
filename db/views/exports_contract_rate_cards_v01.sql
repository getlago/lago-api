SELECT
  crc.organization_id,
  crc.id AS lago_id,
  crc.contract_id AS lago_contract_id,
  crc.rate_card_id AS lago_rate_card_id,
  crc.billing_anchor_date,
  crc.next_billing_at,
  crc.effective_date,
  crc.created_at,
  crc.updated_at,
  crc.deleted_at
FROM contract_rate_cards AS crc;
