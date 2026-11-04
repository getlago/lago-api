# frozen_string_literal: true

class CreateContractRateCardUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_rate_cards_units, id: :uuid do |t|
      t.references :organization, null: false, type: :uuid, foreign_key: true
      t.references :contract_rate_card, null: false, type: :uuid, foreign_key: true, index: false
      t.decimal :units, null: false
      t.date :effective_date, null: false

      t.timestamps
      t.index [:contract_rate_card_id, :effective_date], unique: true, name: "index_contract_rate_cards_units_on_card_and_effective_date"
    end

    reversible do |direction|
      direction.up do
        # Only the new table is written; reading the cards does not block their writers.
        safety_assured do
          execute <<~SQL
            INSERT INTO contract_rate_cards_units (id, organization_id, contract_rate_card_id, units, effective_date, created_at, updated_at)
            SELECT gen_random_uuid(), organization_id, id, units, effective_date, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            FROM contract_rate_cards
            WHERE units IS NOT NULL
          SQL
        end
      end
    end
  end
end
