# frozen_string_literal: true

class AddContractProvenanceToFees < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Without a transaction, an interrupted run keeps what it already applied and
  # a retry starts over, so every step is guarded.
  def change
    add_column :fees, :contract_id, :uuid, if_not_exists: true
    add_column :fees, :contract_rate_card_id, :uuid, if_not_exists: true

    add_index :fees, :contract_id, algorithm: :concurrently, if_not_exists: true
    add_index :fees, :contract_rate_card_id, algorithm: :concurrently, if_not_exists: true
    add_index :contract_rate_cards, [:id, :contract_id], unique: true, algorithm: :concurrently, if_not_exists: true

    add_foreign_key :fees, :contracts, column: :contract_id, validate: false, if_not_exists: true
    add_foreign_key :fees, :contract_rate_cards, column: :contract_rate_card_id, validate: false, if_not_exists: true
    add_foreign_key :fees,
      :contract_rate_cards,
      column: [:contract_rate_card_id, :contract_id],
      primary_key: [:id, :contract_id],
      name: :fk_fees_contract_rate_card_contract,
      validate: false,
      if_not_exists: true

    add_check_constraint :fees,
      "(contract_id IS NULL) = (contract_rate_card_id IS NULL)",
      name: :fees_contract_provenance_present_together,
      validate: false,
      if_not_exists: true
  end
end
