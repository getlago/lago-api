# frozen_string_literal: true

class CreateAgentFreeCreditGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_free_credit_grants, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      # The unique index below serves the lookups by storefront.
      t.references :integration, type: :uuid, null: false, foreign_key: true, index: false
      # The storefront deletes its registrations with delete_all, so the grants go with them at the database level.
      t.references :registration, type: :uuid, null: false, foreign_key: {to_table: :agent_registrations, on_delete: :cascade}
      # Set right after the grant row, in the same transaction: the row is inserted first so that a mailbox that was
      # already served fails before any credit is written.
      t.references :wallet_transaction, type: :uuid, foreign_key: true
      t.string :email_hash, null: false
      t.bigint :amount_cents, null: false
      t.timestamps

      t.index %i[integration_id email_hash], unique: true, name: "index_agent_free_credit_grants_on_integration_and_email_hash"
    end
  end
end
