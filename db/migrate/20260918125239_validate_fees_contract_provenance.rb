# frozen_string_literal: true

class ValidateFeesContractProvenance < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :fees, :contracts, column: :contract_id
    validate_foreign_key :fees, :contract_rate_cards, column: :contract_rate_card_id
    validate_foreign_key :fees,
      :contract_rate_cards,
      column: [:contract_rate_card_id, :contract_id],
      primary_key: [:id, :contract_id],
      name: :fk_fees_contract_rate_card_contract
    validate_check_constraint :fees, name: :fees_contract_provenance_present_together
  end
end
