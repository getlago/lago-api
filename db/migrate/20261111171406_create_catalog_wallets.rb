# frozen_string_literal: true

class CreateCatalogWallets < ActiveRecord::Migration[8.1]
  def change
    create_enum :catalog_wallet_tax_application, %w[tax_on_consumption tax_on_purchase]

    create_table :catalog_wallets, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :contract, type: :uuid, null: false, foreign_key: true, index: false
      t.references :customer, type: :uuid, null: false, foreign_key: true, index: true

      t.string :code, null: false
      t.string :name
      t.string :invoice_display_name
      t.string :currency, null: false
      t.enum :tax_application, enum_type: :catalog_wallet_tax_application, null: false, default: "tax_on_consumption"
      t.integer :priority, null: false, default: 50
      t.bigint :top_up_min_amount_cents
      t.bigint :top_up_max_amount_cents
      t.bigint :balance_cents, null: false, default: 0
      t.bigint :ongoing_balance_cents, null: false, default: 0
      t.boolean :ready_to_be_refreshed, null: false, default: false
      t.datetime :last_ongoing_balance_sync_at

      t.datetime :terminated_at
      t.datetime :deleted_at

      t.timestamps

      t.index %i[contract_id code], unique: true, where: "deleted_at IS NULL"
      t.index :ready_to_be_refreshed, where: "ready_to_be_refreshed"

      t.check_constraint "top_up_min_amount_cents <= top_up_max_amount_cents",
        name: "catalog_wallets_top_up_min_not_above_max"
    end
  end
end
