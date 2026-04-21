# frozen_string_literal: true

class CreateQuoteOwners < ActiveRecord::Migration[8.0]
  def change
    create_table :quote_owners, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :quote, null: false, foreign_key: true, index: false, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.timestamps
      t.index [:quote_id, :user_id], unique: true, name: "index_unique_quote_owners_on_quote_user"
    end
  end
end
