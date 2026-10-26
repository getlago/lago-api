# frozen_string_literal: true

class CreateX402SignInNonces < ActiveRecord::Migration[8.1]
  def change
    create_table :x402_sign_in_nonces, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: false
      t.string :agent_address, null: false
      t.string :nonce, null: false
      t.timestamps

      t.index %i[organization_id agent_address nonce], unique: true, name: "index_x402_sign_in_nonces_on_organization_address_nonce"
      t.index :created_at
    end
  end
end
