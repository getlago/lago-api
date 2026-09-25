# frozen_string_literal: true

class ReplaceContractRateCardEndedDateIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # contract_rate_cards.ended_date is being dropped: the contract end date is
  # the only end of a card. The two indexes carrying the column are rebuilt
  # without it, so the column drop removes nothing still in use.
  def change
    add_index :contract_rate_cards, %i[contract_id rate_card_id],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contract_rate_cards_on_contract_and_rate_card"

    add_index :contract_rate_cards, :next_billing_at,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contract_rate_cards_on_next_billing_at"

    remove_index :contract_rate_cards,
      column: %i[contract_id rate_card_id],
      unique: true,
      where: "deleted_at IS NULL AND ended_date IS NULL",
      algorithm: :concurrently,
      if_exists: true,
      name: "index_active_contract_rate_cards_on_contract_and_card"

    remove_index :contract_rate_cards,
      column: %i[next_billing_at ended_date],
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_exists: true,
      name: "index_contract_rate_cards_on_billing_clock"
  end
end
