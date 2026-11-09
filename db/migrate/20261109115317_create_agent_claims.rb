# frozen_string_literal: true

class CreateAgentClaims < ActiveRecord::Migration[8.1]
  def change
    create_enum :agent_claim_status, %w[issued started verified]

    create_table :agent_claims, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      # The storefront deletes its registrations with delete_all, so the claims go with them at the database level.
      t.references :registration, type: :uuid, null: false, foreign_key: {to_table: :agent_registrations, on_delete: :cascade}
      t.enum :status, enum_type: :agent_claim_status, null: false, default: "issued"
      t.string :code_hash, null: false
      t.string :email
      t.string :verification_code_hash
      t.datetime :verification_expires_at
      t.datetime :verified_at
      t.timestamps

      t.index :code_hash, unique: true
      t.check_constraint "status <> 'verified' OR verified_at IS NOT NULL", name: "check_agent_claims_verified_at"
    end
  end
end
