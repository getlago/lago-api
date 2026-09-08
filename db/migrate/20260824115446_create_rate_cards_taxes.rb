# frozen_string_literal: true

class CreateRateCardsTaxes < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_cards_taxes, id: :uuid do |t|
      t.references :rate_card, type: :uuid, null: false, foreign_key: true
      t.references :tax, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: false, foreign_key: true

      t.index %i[rate_card_id tax_id], unique: true
      t.timestamps
    end
  end
end
