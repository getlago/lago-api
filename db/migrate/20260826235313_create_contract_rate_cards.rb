# frozen_string_literal: true

class CreateContractRateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :contract_rate_cards, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :contract, type: :uuid, null: false, foreign_key: true, index: true
      t.references :rate_card, type: :uuid, null: false, foreign_key: true, index: true

      t.date :billing_anchor_date, null: false
      t.timestamp :next_billing_at, null: false
      t.timestamp :started_at, null: false
      t.timestamp :ended_at
      t.decimal :units
      t.timestamp :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index %i[contract_id rate_card_id],
        unique: true,
        where: "deleted_at IS NULL AND ended_at IS NULL",
        name: "index_active_contract_rate_cards_on_contract_and_card"
      t.index :next_billing_at,
        where: "deleted_at IS NULL AND ended_at IS NULL",
        name: "index_contract_rate_cards_on_next_billing_at"

      t.check_constraint "ended_at IS NULL OR started_at <= ended_at",
        name: "contract_rate_cards_started_before_ended"
    end
  end
end
