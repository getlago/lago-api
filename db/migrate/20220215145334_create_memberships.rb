# frozen_string_literal: true

# CreateMemberships Migration
class CreateMemberships < ActiveRecord::Migration[7.0]
  def change
    create_table :memberships do |t|
      t.references :organization, index: true, null: false
      t.references :user, index: true, null: false
      t.string :role, null: false

      t.timestamps
    end
  end
end
