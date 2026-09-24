# frozen_string_literal: true

class CreateX402Connections < ActiveRecord::Migration[8.0]
  def change
    create_enum :x402_asset, %w[usdc]

    create_table :x402_connections, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.string :code, null: false
      t.string :name, null: false
      t.enum :asset, enum_type: :x402_asset, null: false, default: "usdc"
      t.string :secrets
      t.jsonb :payout_addresses, null: false, default: {}
      t.string :networks, array: true, null: false, default: []
      t.datetime :deleted_at
      t.timestamps

      t.index %i[organization_id code], unique: true, where: "deleted_at IS NULL"
    end
  end
end
