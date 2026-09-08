# frozen_string_literal: true

class IndexDueContractRateCards < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :contract_rate_cards, :next_billing_at,
      where: "deleted_at IS NULL AND next_billing_at IS NOT NULL",
      name: "index_contract_rate_cards_on_due_billing", algorithm: :concurrently
  end
end
