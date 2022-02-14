# frozen_string_literal: true

# CreateUsers Migration
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'pgcrypto'
    create_table :users, id: :uuid do |t|
      t.string :email
      t.string :password_digest

      t.timestamps
    end
  end
end
