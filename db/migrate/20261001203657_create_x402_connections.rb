# frozen_string_literal: true

class CreateX402Connections < ActiveRecord::Migration[8.0]
  def change
    create_enum :x402_facilitator, %w[coinbase_cdp]
    create_enum :x402_asset, %w[usdc]

    create_table :x402_connections, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: false
      t.string :code, null: false
      t.string :name, null: false
      t.enum :facilitator, enum_type: :x402_facilitator, null: false, default: "coinbase_cdp"
      t.string :secrets, null: false
      t.jsonb :payout_addresses, null: false, default: {}
      t.string :networks, array: true, null: false, default: []
      t.enum :asset, enum_type: :x402_asset, null: false, default: "usdc"
      t.boolean :auto_create_customers, null: false, default: true
      t.datetime :deleted_at
      t.timestamps

      t.index %i[organization_id code], unique: true, where: "deleted_at IS NULL"
    end
  end
end
