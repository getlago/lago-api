# frozen_string_literal: true

class CreateCommitments < ActiveRecord::Migration[7.0]
  def change
    create_table :commitments, id: :uuid do |t|
      t.references :plan, null: false, index: true, foreign_key: true, type: :uuid
      t.integer :commitment_type, null: false
      t.bigint :amount_cents, null: false
      t.string :invoice_display_name

      t.timestamps
    end

    add_index :commitments, [:commitment_type, :plan_id], unique: true
  end
end
