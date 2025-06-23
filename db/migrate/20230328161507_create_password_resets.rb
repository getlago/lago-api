# frozen_string_literal: true

class CreatePasswordResets < ActiveRecord::Migration[7.0]
  def change
    create_table :password_resets, id: :uuid do |t|
      t.references :user, index: true, null: false, foreign_key: true, type: :uuid

      t.string :token, null: false, index: {unique: true}

      t.datetime :expire_at, null: false

      t.timestamps
    end
  end
end
