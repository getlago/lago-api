# frozen_string_literal: true

class AddInvites < ActiveRecord::Migration[7.0]
  def change
    create_table :invites, id: :uuid do |t|
      t.references :organization, index: true, null: false, foreign_key: true, type: :uuid
      t.references :membership, index: true, null: true, foreign_key: true, type: :uuid

      t.string :email, null: false
      t.string :token, null: false, index: {unique: true}
      t.integer :status, null: false, default: 0

      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end
  end
end
