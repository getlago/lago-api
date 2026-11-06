# frozen_string_literal: true

class CreateAppliedWalletExpirations < ActiveRecord::Migration[8.0]
  def change
    create_table :applied_wallet_expirations, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :invoice, type: :uuid, null: false, foreign_key: true, index: {unique: true}
      t.references :wallet, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
  end
end
